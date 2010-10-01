module Sunshine

  ##
  # Unregister a sunshine app.
  #
  # Usage: sunshine rm [options] app_name [more names...]
  #
  # Arguments:
  #     app_name      Name of the application to remove.
  #
  # Options:
  #   -d, --delete               Delete the app directory.
  #   -f, --format FORMAT        Set the output format (txt, yml, json)
  #   -u, --user USER            User to use for remote login. Use with -r.
  #   -r, --remote svr1,svr2     Run on one or more remote servers.
  #   -S, --sudo                 Run remote commands using sudo or sudo -u USER
  #   -v, --verbose              Run in verbose mode.

  class RmCommand < ListCommand

    ##
    # Takes an array and a hash, runs the command and returns:
    #   true: success
    #   false: failed
    #   exitcode:
    #     code == 0: success
    #     code != 0: failed
    # and optionally an accompanying message.


    def self.exec names, config
      delete_dir = config['delete_dir']

      output = exec_each_server config do |shell|
        server_command = new(shell)
        results        = server_command.remove(names, delete_dir)

        self.save_list server_command.app_list, shell

        results
      end

      return output
    end


    ##
    # Remove a registered app on a given deploy server

    def remove app_names, delete_dir=false
      each_app(*app_names) do |server_app|
        if delete_dir
          server_app.stop rescue nil
          server_app.shell.call "rm -rf #{server_app.root_path}"

          server_app.crontab.delete!
        end

        @app_list.delete server_app.name
      end
    end


    ##
    # Parses the argv passed to the command

    def self.parse_args argv
      parse_remote_args(argv) do |opt, options|
        opt.banner = <<-EOF

Usage: #{opt.program_name} rm [options] app_name [more names...]

Arguments:
    app_name      Name of the application to remove.
        EOF

        opt.on('-d', '--delete',
               'Delete the app directory.') do
          options['delete_dir'] = true
        end
      end
    end
  end
end
