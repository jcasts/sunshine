module Sunshine

  ##
  # Runs the start script of all specified sunshine apps.
  #
  # Usage: sunshine start app_name [more names...] [options]
  #
  # Arguments:
  #     app_name     Name of the application to start.
  #
  # Options:
  #     -F, --force                Stop apps that are running, then start them.
  #     -u, --user USER            User to use for remote login. Use with -r.
  #     -r, --remote svr1,svr2     Run on one or more remote servers.
  #     -v, --verbose              Run in verbose mode.

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

      output = exec_each_server config do |deploy_server|
        new(deploy_server).start(names, force)
      end

      return output
    end


    ##
    # Start specified apps.

    def start app_names, force=false
      each_app(*app_names) do |name, path|

        @deploy_server.call "#{path}/stop" if running?(path) && force

        begin
          @deploy_server.call "#{path}/start"
          text_status path

        rescue CmdError => e
          raise "Could not start. #{text_status(path)}"
        end
      end
    end


    ##
    # Parses the argv passed to the command

    def self.parse_args argv
      parse_remote_args(argv) do |opt, options|
        opt.banner = <<-EOF

Usage: #{opt.program_name} start app_name [more names...] [options]

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

