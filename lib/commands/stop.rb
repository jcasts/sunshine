module Sunshine

  module StopCommand

    def self.exec argv, config
      app_names = argv
      ListCommand.each_server(config['servers']) do |apps, server|
        app_names.each do |name|
          path = apps[name]
          server.run File.join(app_path, "stop")
        end
      end
    end


    def self.parse_args argv
      DefaultCommand.parse_remote_args(argv) do |opt|
        opt.banner = <<-EOF

Usage: #{opt.program_name} stop app_name [more names...] [options]

Arguments:
    app_name     Name of the application to stop.
        EOF

      end
    end
  end
end

