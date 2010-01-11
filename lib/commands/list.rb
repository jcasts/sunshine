module Sunshine

  module ListCommand

    def self.exec argv, config

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

        opt.on('-i', '--installed',
               'Check if app is installed. See also "sunshine add/rm".') do
          options['return'] = :installed
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
