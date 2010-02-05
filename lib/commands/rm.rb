module Sunshine

  ##
  # Unregister a sunshine app.
  #
  # Usage: sunshine rm app_name [more names...] [options]
  #
  # Arguments:
  #     app_name      Name of the application to remove.
  #
  # Options:
  #     -d, --delete               Delete the app directory.
  #     -u, --user USER            User to use for remote login. Use with -r.
  #     -r, --remote svr1,svr2     Run on one or more remote servers.
  #     -v, --verbose              Run in verbose mode.

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

      output = exec_each_server config do |deploy_server|
        server_command = new(deploy_server)
        results        = server_command.remove(delete_dir, *names)

        self.save_list server_command.app_list, deploy_server

        results
      end

      return output
    end


    ##
    # Remove a registered app on a given deploy server

    def remove(delete_dir, *app_names)
      each_app(*app_names) do |name, path|
        if delete_dir
          @deploy_server.call File.join(path, "stop")
          @deploy_server.call "rm -rf #{path}"

          Crontab.new(name).delete! @deploy_server
        end

        @app_list.delete name
      end
    end


    ##
    # Parses the argv passed to the command

    def self.parse_args argv
      parse_remote_args(argv) do |opt, options|
        opt.banner = <<-EOF

Usage: #{opt.program_name} rm app_name [more names...] [options]

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
