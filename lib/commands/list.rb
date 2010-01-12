module Sunshine

  module ListCommand

    def self.exec argv, config
      errors = false
      out = []
      boolean_output = config['return_type'] == :boolean

      each_server_list(config['servers']) do |list, server|
        app_names = argv.empty? ? list.keys : argv

        next if app_names.empty?

        separator = "-" * server.host.length

        out.concat [separator, server.host, separator]

        app_names.each do |name|
          out << "#{name} -> #{list[name] || '?'}"

          unless list[name]
            errors = true
            exit_with_value(false, errors) if boolean_output
            next
          end

          out << case config['return']
          when :details
            server.run("cat #{list[name]}/info")
          when :health
            
          when :status
            s = server.run("#{list[name]}/status") && "running" rescue "stopped"
            exit_with_value(false, errors) if s == "stopped" && boolean_output
            s
          end

          out.last << "\n"
        end

        out.last << "\n"
      end

      out = boolean_output ? !errors : out.join("\n")
      exit_with_value out, errors
    end


    def self.exit_with_value val, errors
      output = errors ? $stderr : $stdout
      exitcode = errors ? 1 : 0

      output << "#{val}\n"

      exit exitcode
    end

    def self.load_list server
      YAML.load(server.run(Sunshine::READ_LIST_CMD)) || {}
    end


    def self.save_list list, server
      server.run "echo '#{list.to_yaml}' > #{Sunshine::APP_LIST_PATH}"
    end


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

        opt.on('-h', '--health [STATUS]', [:on, :off],
               'Set or get the healthcheck status (on, off).') do |status|
          options['health'] = status
          options['return'] = :health
        end
      end
    end
  end
end
