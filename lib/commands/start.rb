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
  #     -f, --force                Stop apps that are running, then start them.
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

    def self.exec app_names, config
      errors = false

      each_server_list(config['servers']) do |apps, server|
        app_names.each do |name|
          app_path = apps[name]
          unless app_path
            errors = true
            next
          end

          running = server.call File.join(app_path, "status") rescue false

          if running && config['force']
            server.call File.join(app_path, "stop")
            running = false
          end

          server.call File.join(app_path, "start") unless running
        end
      end

      return !errors
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

        opt.on('-f', '--force',
               'Stop apps that are running before starting them again.') do
          options['force'] = true
        end
      end
    end
  end
end

