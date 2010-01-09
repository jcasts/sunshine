module Sunshine

  module AddCommand

    def self.exec argv, config
      app_paths = argv
      servers = config['servers'] || [Sunshine.console]

      servers.each do |server|
        host = server.host rescue "localhost"
        puts "Updating #{host}..." if config['verbose']
        log_arr = []

        server.connect if server.respond_to? :connect

        apps = YAML.load server.run(Sunshine::READ_LIST_CMD)
        apps ||= {}

        app_paths.each do |path|
          app_name, path = path.split(":") if path.include?(":")
          app_name ||= File.basename path

          unless (server.run "test -d #{path}" rescue false)
            puts "  #{path} is not a valid directory"
            next
          end

          apps[app_name] = path

          log_arr << "  add: #{app_name} -> #{path}"
        end

        server.run "echo '#{apps.to_yaml}' > #{Sunshine::APP_LIST_PATH}"
        server.disconnect if server.respond_to? :disconnect

        puts "#{log_arr.join("\n")}" if config['verbose']
      end
    end


    def self.parse_args argv

      DefaultCommand.parse_remote_args(argv) do |opt|
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
