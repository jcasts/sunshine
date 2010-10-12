module Sunshine

  ##
  # Runs the start script of all specified sunshine apps.
  #
  # Usage: sunshine start [options] app_name [more names...]
  #
  # Arguments:
  #     app_name     Name of the application to start.
  #
  # Options:
  #   -F, --force                Stop apps that are running, then start them.
  #   -f, --format FORMAT        Set the output format (txt, yml, json)
  #   -u, --user USER            User to use for remote login. Use with -r.
  #   -r, --remote svr1,svr2     Run on one or more remote servers.
  #   -S, --sudo                 Run remote commands using sudo or sudo -u USER
  #   -v, --verbose              Run in verbose mode.

  class StartCommand < ListCommand

    ##
    # Takes an array and a hash, runs the command and returns:
    #   true: success
    #   false: failed
    #   exitcode:
    #     code == 0: success
    #     code != 0: failed
    # and optionally an accompanying message.

    def self.exec names, config
      force = config['force']

      output = exec_each_server config do |shell|
        new(shell).start(names, force)
      end

      return output
    end


    ##
    # Start specified apps.

    def start app_names, force=false
      status_after_command :start, app_names, :sudo => false do |server_app|

        server_app.stop if server_app.running? && force
      end
    end


    ##
    # Parses the argv passed to the command

    def self.parse_args argv
      parse_remote_args(argv) do |opt, options|
        opt.banner = <<-EOF

Usage: #{opt.program_name} start [options] app_name [more names...]

Arguments:
    app_name     Name of the application to start.
        EOF

        opt.on('-F', '--force',
               'Stop apps that are running before starting them again.') do
          options['force'] = true
        end
      end
    end
  end
end

