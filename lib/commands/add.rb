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

          log_arr << "  #{app_name} -> #{path}"
        end

        server.run "echo '#{apps.to_yaml}' > #{Sunshine::APP_LIST_PATH}"
        server.disconnect if server.respond_to? :disconnect

        puts "#{log_arr.join("\n")}" if config['verbose']
      end
    end


    def self.parse_args argv
      options = {}

      opts = OptionParser.new do |opt|
        opt.program_name = File.basename $0
        opt.version = Sunshine::VERSION
        opt.release = nil
        opt.banner = <<-EOF

Usage: #{opt.program_name} add app_path [more paths...] [options]

Arguments:
    app_path      Path to the application to add.
                  A name may be assigned to the app by specifying name:app_path.
                  By default: name = File.basename app_path
        EOF

        opt.separator nil
        opt.separator "Options:"

        opt.on('-u', '--user USER',
               'User to use for remote login. Use with -r.') do |value|
          options['user'] = value
        end

        opt.on('-r', '--remote server1,server2', Array,
               'Run on one or more remote servers') do |servers|
          options['servers'] = servers
        end

        opt.on('-v', '--verbose') do
          options['verbose'] = true
        end
      end

      opts.parse! argv

      if options['servers']
        options['servers'].map! do |host|
          DeployServer.new host, :user => options['user']
        end
        options['servers'] = DeployServerDispatcher.new(*options['servers'])
      end

      options
    end
  end
end
