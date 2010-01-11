module Sunshine

  module AddCommand

    def self.exec argv, config
      app_paths = argv

      ListCommand.each_server_list(config['servers']) do |apps, server|
        puts "Updating #{host}..." if config['verbose']

        app_paths.each do |path|
          app_name, path = path.split(":") if path.include?(":")
          app_name ||= File.basename path

          unless (server.run "test -d #{path}" rescue false)
            puts "  #{path} is not a valid directory"
            next
          end

          apps[app_name] = path

          puts "  add: #{app_name} -> #{path}" if config['verbose']
        end

        ListCommand.save_list apps, server
      end
    end


    def self.parse_args argv

      DefaultCommand.parse_remote_args(argv) do |opt, options|
        opt.banner = <<-EOF

Usage: #{opt.program_name} add app_path [more paths...] [options]

Arguments:
    app_path      Path to the application to add.
                  A name may be assigned to the app by specifying name:app_path.
                  By default: name = File.basename app_path
        EOF
      end
    end
  end
end
