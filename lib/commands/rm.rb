module Sunshine

  module RmCommand

    def self.exec argv, config
      app_names = argv
      servers = config['servers'] || [Sunshine.console]

      servers.each do |server|
        host = server.host rescue "localhost"
        puts "Updating #{host}..." if config['verbose']
        log_arr = []

        server.connect if server.respond_to? :connect

        apps = YAML.load server.run(Sunshine::READ_LIST_CMD)
        apps ||= {}

        app_names.each do |app_name|

          unless apps.has_key?(app_name)
            puts "  #{app_name} is not a valid app name"
            next
          end

          path = apps[app_name]

          if config['delete_dir']
            cmd = "#{path}/stop && rm -rf #{path}"
            cmd = "sudo #{cmd}" if config['delete_dir'] == :sudo
            server.run cmd
          end

          apps.delete(app_name)

          log_arr << "  rm: #{app_name} -> #{path}"
        end

        server.run "echo '#{apps.to_yaml}' > #{Sunshine::APP_LIST_PATH}"
        server.disconnect if server.respond_to? :disconnect

        puts "#{log_arr.join("\n")}" if config['verbose']
      end
    end


    def self.parse_args argv
      DefaultCommand.parse_remote_args(argv) do |opt|
        opt.banner = <<-EOF

Usage: #{opt.program_name} rm app_name [more names...] [options]

Arguments:
    app_name      Name of the application to remove.
        EOF

        opt.on('-d', '--delete',
               'Delete the app directory.') do
          options['delete_dir'] = true
        end

        opt.on('-D', '--sudo-delete',
               'Delete the app directory using sudo.') do
          options['delete_dir'] = :sudo
        end
      end
    end
  end
end
