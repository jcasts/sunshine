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
  #   -f, --format FORMAT      Set the output format (txt, yml, json)
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

      output = exec_each_server config do |shell|
        new(shell).send(action, *args)
      end

      return output
    end


    ##
    # Executes common list functionality for each deploy server.

    def self.exec_each_server config
      shells = config['servers']
      format = config['format']

      responses = {}
      success   = true

      shells.each do |shell|
        shell.connect

        begin
          state, response = yield(shell)
        rescue => e
          state = false
          response = "#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
        end

        host            = shell.host
        success         = state if success
        responses[host] = build_response state, response

        shell.disconnect
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



    attr_accessor :app_list, :shell

    def initialize shell
      @shell    = shell
      @app_list = self.class.load_list @shell
    end


    ##
    # Reads and returns the specified apps' info file.
    # Returns a response hash (see ListCommand#each_app).

    def details(*app_names)
      each_app(*app_names) do |server_app|
        "\n#{server_app.deploy_details.to_yaml}"
      end
    end


    ##
    # Returns the path of specified apps.
    # Returns a response hash (see ListCommand#each_app).

    def exist?(*app_names)
      each_app(*app_names) do |server_app|
        server_app.root_path
      end
    end


    ##
    # Get or set the healthcheck state.
    # Returns a response hash (see ListCommand#each_app).

    def health(*app_names)
      action = app_names.delete_at(0) if Symbol === app_names.first

      each_app(*app_names) do |server_app|
        server_app.health.send action if action
        server_app.health.status
      end
    end


    ##
    # Checks if the apps' pids are present.
    # Returns a response hash (see ListCommand#each_app).

    def status(*app_names)
      each_app(*app_names) do |server_app|
        server_app.status
      end
    end


    ##
    # Runs a command and returns the status for each app_name:
    #   status_after_command 'restart', ['app1', 'app2']

    def status_after_command cmd, app_names
      each_app(*app_names) do |server_app|

        yield(server_app) if block_given?

        begin
          server_app.send cmd.to_sym
          server_app.running? ? 'running' : 'down'

        rescue CmdError => e
          raise "Failed running #{cmd}: #{server_app.status}"
        end
      end
    end


    # Do something with each server app and build a response hash:
    #   each_app do |server_app|
    #     ...
    #   end
    #
    # Restrict it to a set of apps if they are present on the server:
    #   each_app('app1', 'app2') do |server_app|
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

        server_app = ServerApp.new name, @shell, :root_path => path

        yield(server_app) if block_given?
      end
    end


    ##
    # Builds a response object for each item passed and returns
    # the result of the passed block as its data value.

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
      path = server.expand_path Sunshine::APP_LIST_PATH
      server.make_file path, list.to_yaml
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
