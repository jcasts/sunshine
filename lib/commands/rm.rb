module Sunshine

  module RmCommand

    def self.exec argv, config
      app_names = argv

      ListCommand.each_server_list(config['servers']) do |apps, server|
        puts "Updating #{host}..." if config['verbose']

        app_names.each do |app_name|

          unless apps.has_key?(app_name)
            puts "  #{app_name} is not a valid app name"
            next
          end

          path = apps[app_name]

          #TODO: remove crontab jobs or consider full uninstall
          if config['delete_dir']
            server.run File.join(path, "stop")
            cmd = "rm -rf #{path}"
            cmd = "sudo #{cmd}" if config['delete_dir'] == :sudo
            server.run cmd
          end

          apps.delete(app_name)

          puts "  rm: #{app_name} -> #{path}" if config['verbose']
        end

        ListCommand.save_list apps, server
      end
    end


    def self.parse_args argv
      DefaultCommand.parse_remote_args(argv) do |opt, options|
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
