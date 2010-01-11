module Sunshine

  module StartCommand

    def self.exec argv, config
      app_names = argv
      ListCommand.each_server(config['servers']) do |apps, server|
        app_names.each do |name|
          path = apps[name]
          server.run File.join(app_path, "start")
        end
      end
    end


    def self.parse_args argv
      DefaultCommand.parse_remote_args(argv) do |opt|
        opt.banner = <<-EOF

Usage: #{opt.program_name} start app_name [more names...] [options]

Arguments:
    app_name     Name of the application to start.
        EOF

        opt.on('-f', '--force',
               'Restart apps that are running.') do
          options['force'] = true
        end
      end
    end
  end
end

