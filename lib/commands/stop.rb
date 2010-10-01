module Sunshine

  ##
  # Runs the stop script of all specified sunshine apps.
  #
  # Usage: sunshine stop [options] app_name [more names...]
  #
  # Arguments:
  #     app_name     Name of the application to stop.
  #
  # Options:
  #   -f, --format FORMAT        Set the output format (txt, yml, json)
  #   -u, --user USER            User to use for remote login. Use with -r.
  #   -r, --remote svr1,svr2     Run on one or more remote servers.
  #   -S, --sudo                 Run remote commands using sudo or sudo -u USER
  #   -v, --verbose              Run in verbose mode.

  class StopCommand < ListCommand

    ##
    # Takes an array and a hash, runs the command and returns:
    #   true: success
    #   false: failed
    #   exitcode:
    #     code == 0: success
    #     code != 0: failed
    # and optionally an accompanying message.

    def self.exec names, config
      output = exec_each_server config do |shell|
        new(shell).stop(names)
      end

      return output
    end


    ##
    # Stop specified apps.

    def stop app_names
      status_after_command :stop, app_names
    end

    ##
    # Parses the argv passed to the command

    def self.parse_args argv
      parse_remote_args(argv) do |opt, options|
        opt.banner = <<-EOF

Usage: #{opt.program_name} stop [options] app_name [more names...]

Arguments:
    app_name     Name of the application to stop.
        EOF

      end
    end
  end
end

