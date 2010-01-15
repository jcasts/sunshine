module Sunshine

  module StartCommand

    ##
    # Runs the command and returns:
    #   true: success
    #   false: failed
    #   exitcode:
    #     code == 0: success
    #     code != 0: failed
    # and optionally an accompanying message.

    def self.exec app_names, config
      errors = false

      ListCommand.each_server_list(config['servers']) do |apps, server|
        app_names.each do |name|
          app_path = apps[name]
          unless app_path
            errors = true
            next
          end

          running = server.run File.join(app_path, "status") rescue false

          if running && config['force']
            server.run File.join(app_path, "stop")
            running = false
          end

          server.run File.join(app_path, "start") unless running
        end
      end

      return !errors
    end


    def self.parse_args argv
      DefaultCommand.parse_remote_args(argv) do |opt, options|
        opt.banner = <<-EOF

Usage: #{opt.program_name} start app_name [more names...] [options]

Arguments:
    app_name     Name of the application to start.
        EOF

        opt.on('-f', '--force',
               'Stop apps that are running before starting them again.') do
          options['force'] = true
        end
      end
    end
  end
end

