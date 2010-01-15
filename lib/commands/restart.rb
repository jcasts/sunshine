module Sunshine

  module RestartCommand

    ##
    # Runs the command and returns:
    #   true: success
    #   false: failed
    #   exitcode:
    #     code == 0: success
    #     code != 0: failed
    # and optionally an accompanying message.

    def self.exec argv, config
      app_names = argv

      ListCommand.each_server_list(config['servers']) do |apps, server|
        app_names.each do |name|
          app_path = apps[name]
          server.run File.join(app_path, "restart")
        end
      end

      return true
    end


    def self.parse_args argv
      DefaultCommand.parse_remote_args(argv) do |opt, options|
        opt.banner = <<-EOF

Usage: #{opt.program_name} restart app_name [more names...] [options]

Arguments:
    app_name     Name of the application to restart.
        EOF

      end
    end
  end
end

