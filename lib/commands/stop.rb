module Sunshine

  ##
  # Runs the stop script of all specified sunshine apps.
  #
  # Usage: sunshine stop app_name [more names...] [options]
  #
  # Arguments:
  #     app_name     Name of the application to stop.
  #
  # Options:
  #     -u, --user USER            User to use for remote login. Use with -r.
  #     -r, --remote svr1,svr2     Run on one or more remote servers.
  #     -v, --verbose              Run in verbose mode.

  class StopCommand < ListCommand

    ##
    # Takes an array and a hash, runs the command and returns:
    #   true: success
    #   false: failed
    #   exitcode:
    #     code == 0: success
    #     code != 0: failed
    # and optionally an accompanying message.

    def self.exec app_names, config

      each_server_list(config['servers']) do |apps, server|
        app_names.each do |name|
          app_path = apps[name]
          server.call File.join(app_path, "stop")
        end
      end

      return true
    end


    ##
    # Parses the argv passed to the command

    def self.parse_args argv
      parse_remote_args(argv) do |opt, options|
        opt.banner = <<-EOF

Usage: #{opt.program_name} stop app_name [more names...] [options]

Arguments:
    app_name     Name of the application to stop.
        EOF

      end
    end
  end
end

