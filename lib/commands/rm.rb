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
  #     -D, --sudo-delete          Delete the app directory using sudo.
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

    def self.exec app_names, config

      each_server_list(config['servers']) do |apps, server|
        puts "Updating #{server.host}..." if config['verbose']

        app_names.each do |app_name|

          unless apps.has_key?(app_name)
            puts "  #{app_name} is not a valid app name"
            next
          end

          path = apps[app_name]

          if config['delete_dir']
            server.call File.join(path, "stop")
            cmd = "rm -rf #{path}"
            cmd = "sudo #{cmd}" if config['delete_dir'] == :sudo
            server.call cmd

            Crontab.new(app_name).delete! server
          end

          apps.delete(app_name)

          puts "  rm: #{app_name} -> #{path}" if config['verbose']
        end

        save_list apps, server
      end

      return true
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

        opt.on('-D', '--sudo-delete',
               'Delete the app directory using sudo.') do
          options['delete_dir'] = :sudo
        end
      end
    end
  end
end
