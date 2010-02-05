require 'json'

module Sunshine

  ##
  # List and perform simple state actions on lists of sunshine apps.
  #
  # Usage: sunshine list app_name [more names...] [options]
  #
  # Arguments:
  #   app_name      Name of an application to list.
  #
  # Options:
  #   -s, --status             Check if an app is running.
  #   -d, --details            Get details about the deployed apps.
  #   -h, --health [STATUS]    Set or get the healthcheck status.
  #                            (enable, disable, remove)
  #   -u, --user USER          User to use for remote login. Use with -r
  #   -r, --remote svr1,svr2   Run on one or more remote servers.
  #   -v, --verbose            Run in verbose mode.

  class ListCommand < DefaultCommand

    ##
    # Takes an array and a hash, runs the command and returns:
    #   true: success
    #   false: failed
    #   exitcode:
    #     code == 0: success
    #     code != 0: failed
    # and optionally an accompanying message.

    def self.exec names, config
      action = config['return'] || :exist?

      args = config[action.to_s] || []
      args = [args, names].flatten

      output = exec_each_server config do |deploy_server|
        new(deploy_server).send(action, *args)
      end

      return output
    end


    ##
    # Executes common list functionality for each deploy server.

    def self.exec_each_server config
      deploy_servers = config['servers']
      format         = config['format']

      responses = {}
      success   = true

      deploy_servers.each do |deploy_server|

        begin
          state, response = yield(deploy_server)
        rescue => e
          state = false
          response = "#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
        end

        host            = deploy_server.host
        success         = state if success
        responses[host] = build_response state, response
      end

      output = format ? self.send(format, responses) : responses
      return success, output
    end


    ##
    # Formats response as text output:
    #   ------------------
    #   subdomain.host.com
    #   ------------------
    #   app_name: running

    def self.txt_format res_hash
      str_out = ""

      res_hash.each do |host, response|
        separator = "-" * host.length

        host_status = if Hash === response[:data]
          apps_status = response[:data].map do |app_name, status|
            "#{app_name}: #{status[:data]}\n"
          end
          apps_status.join("\n")

        else
          response[:data]
        end

        str_out << "\n"
        str_out << [separator, host, separator].join("\n")
        str_out << "\n"
        str_out << host_status
        str_out << "\n"
      end

      str_out
    end


    ##
    # Formats response as yaml:

    def self.yml_format res_hash
      res_hash.to_yaml
    end


    ##
    # Formats response as json:

    def self.json_format res_hash
      res_hash.to_json
    end



    attr_accessor :app_list, :deploy_server

    def initialize deploy_server
      @deploy_server = deploy_server
      @deploy_server.connect rescue nil

      @app_list = self.class.load_list @deploy_server
    end


    ##
    # Reads and returns the specified apps' info file.
    # Returns a response hash (see ListCommand#each_app).

    def details(*app_names)
      each_app(*app_names) do |name, path|
        output = @deploy_server.call "cat #{path}/info"
        "\n#{output}"
      end
    end


    ##
    # Returns the path of specified apps.
    # Returns a response hash (see ListCommand#each_app).

    def exist?(*app_names)
      each_app(*app_names) do |name, path|
        path
      end
    end


    ##
    # Get or set the healthcheck statue.
    # Returns a response hash (see ListCommand#each_app).

    def health(*app_names)
      action = app_names.delete_at(0) if Symbol === app_names.first

      each_app(*app_names) do |name, path|
        health = Healthcheck.new "#{path}/shared", @deploy_server
        health.send action if action

        health.status.values.first
      end
    end


    ##
    # Checks if the apps' pids are present.
    # Returns a response hash (see ListCommand#each_app).

    def status(*app_names)
      each_app(*app_names) do |name, path|
        text_status path
      end
    end


    ##
    # Get an app's status

    def text_status path
      running?(path) && "running" || "down"
    end


    ##
    # Check if an app is running

    def running? path
      @deploy_server.call "#{path}/status" rescue false
    end

    # Do something with each server app it to a set of app names
    # and build a response hash:
    #   each_app do |name, path|
    #     ...
    #   end
    #
    # Restrict it to a set of apps if they are present on the server:
    #   each_app('app1', 'app2') do |name, path|
    #     ...
    #   end
    #
    # Returns a response hash:
    #   {"app_name" => {:success => true, :data => "somedata"} ...}

    def each_app(*app_names)
      app_names = @app_list.keys if app_names.empty?

      response_for_each(*app_names) do |name|
        path = @app_list[name]

        raise "Application not found." unless path

        yield(name, path) if block_given?
      end
    end


    def response_for_each(*items)
      response  = {}
      success   = true

      items.each do |item|

        begin
          data = yield(item) if block_given?

          response[item] = self.class.build_response true, data

        rescue => e
          success = false
          response[item] = self.class.build_response false, e.message
        end

      end

      [success, response]
    end


    ##
    # Builds a standard response entry:
    #   {:success => true, :data => "somedata"}

    def self.build_response success, data=nil
      {:success => success, :data => data}
    end


    ##
    # Load the app list yaml file from the server.

    def self.load_list server
      list = YAML.load(server.call(Sunshine::READ_LIST_CMD))
      list = {} unless Hash === list
      list
    end


    ##
    # Write the app list hash to the remote server.

    def self.save_list list, server
      server.call "echo '#{list.to_yaml}' > #{Sunshine::APP_LIST_PATH}"
    end


    ##
    # Do something which the installed apps list on each server.
    #   each_server_list(deploy_servers) do |list, server|
    #     list    #=> {app_name => app_path, ...}
    #   end

    def self.each_server_list servers
      servers.each do |server|
        host = server.host rescue "localhost"
        log_arr = []

        server.connect if server.respond_to? :connect

        apps = load_list server

        yield(apps, server) if block_given?

        server.disconnect if server.respond_to? :disconnect
      end
    end


    ##
    # Parses the argv passed to the command

    def self.parse_args argv
      parse_remote_args(argv) do |opt, options|
        opt.banner = <<-EOF

Usage: #{opt.program_name} list app_name [more names...] [options]

Arguments:
    app_name      Name of an application to list.
        EOF

        opt.on('-s', '--status',
               'Check if an app is running.') do
          options['return'] = :status
        end

        opt.on('-d', '--details',
               'Get details about the deployed apps.') do
          options['return'] = :details
        end


        vals = [:enable, :disable, :remove]
        desc = "Set or get the healthcheck status. (#{vals.join(", ")})"

        opt.on('-h', '--health [STATUS]', vals, desc) do |status|
          options['health'] = status.to_sym if status
          options['return'] = :health
        end
      end
    end
  end
end
