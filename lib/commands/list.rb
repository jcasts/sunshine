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
  #   -b, --bool               Return a boolean when performing list action.
  #   -s, --status             Check if an app is running.
  #   -d, --details            Get details about the deployed apps.
  #   -h, --health [STATUS]    Set or get the healthcheck status
  #                            (enable, disable, remove)
  #   -u, --user USER          User to use for remote login. Use with -r.
  #   -r, --remote svr1,svr2   Run on one or more remote servers
  #   -v, --verbose            Run in verbose mode

  module ListCommand

    ##
    # Takes an array and a hash, runs the command and returns:
    #   true: success
    #   false: failed
    #   exitcode:
    #     code == 0: success
    #     code != 0: failed
    # and optionally an accompanying message.

    def self.exec names, config
      errors = false
      out = []
      boolean_output = config['return_type'] == :boolean

      each_server_list(config['servers']) do |list, server|
        app_names = names.empty? ? list.keys : names

        next if app_names.empty?

        separator = "-" * server.host.length

        out.concat [separator, server.host, separator]

        app_names.each do |name|
          app_path = list[name]
          out << "#{name} -> #{app_path || '?'}"

          unless app_path
            errors = true
            return !errors, false if boolean_output
            next
          end


          out << case config['return']

          when :details
            server.run("cat #{app_path}/info")

          when :health
            health = Healthcheck.new "#{app_path}/shared", [server]
            health.send config['health'] if config['health']
            h = health.status.values.first
            return !errors, false if h != :ok && boolean_output
            h

          when :status
            s = server.run("#{app_path}/status") && "running" rescue "stopped"
            return !errors, false if s == "stopped" && boolean_output
            s
          end.to_s

          out.last << "\n"
        end

        out.last << "\n"
      end

      out = boolean_output ? !errors : out.join("\n")
      return !errors, out
    end


    ##
    # Load the app list yaml file from the server.

    def self.load_list server
      list = YAML.load(server.run(Sunshine::READ_LIST_CMD))
      list = {} unless Hash === list
      list
    end


    ##
    # Write the app list hash to the remote server.

    def self.save_list list, server
      server.run "echo '#{list.to_yaml}' > #{Sunshine::APP_LIST_PATH}"
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

        apps = ListCommand.load_list server

        yield(apps, server) if block_given?

        server.disconnect if server.respond_to? :disconnect
      end
    end


    ##
    # Parses the argv passed to the command

    def self.parse_args argv
      DefaultCommand.parse_remote_args(argv) do |opt, options|
        opt.banner = <<-EOF

Usage: #{opt.program_name} list app_name [more names...] [options]

Arguments:
    app_name      Name of an application to list.
        EOF

        opt.on('-b', '--bool',
               'Return a boolean when performing list action.') do
          options['return_type'] = :boolean
        end

        opt.on('-s', '--status',
               'Check if an app is running.') do
          options['return'] = :status
        end

        opt.on('-d', '--details',
               'Get details about the deployed apps.') do
          options['return'] = :details
        end


        vals = [:enable, :disable, :remove]
        desc = "Set or get the healthcheck status (#{vals.join(", ")})"

        opt.on('-h', '--health [STATUS]', vals, desc) do |status|
          options['health'] = status
          options['return'] = :health
        end
      end
    end
  end
end
