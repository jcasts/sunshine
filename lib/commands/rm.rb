module Sunshine

  module RmCommand

    def self.exec argv, config
      app_names = argv
      servers = config['servers'] || [Sunshine.console]

      servers.each do |server|
        host = server.host rescue "localhost"
        puts "Updating #{host}..." if config['verbose']
        log_arr = []

        server.connect if server.respond_to? :connect

        apps = YAML.load server.run(Sunshine::READ_LIST_CMD)
        apps ||= {}

        app_names.each do |app_name|

          unless apps.has_key?(app_name)
            puts "  #{app_name} is not a valid app name"
            next
          end

          path = apps[app_name]

          if config['delete_dir']
            cmd = "#{path}/stop && rm -rf #{path}"
            cmd = "sudo #{cmd}" if config['delete_dir'] == :sudo
            server.run cmd
          end

          apps.delete(app_name)

          log_arr << "  rm: #{app_name} -> #{path}"
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

Usage: #{opt.program_name} rm app_name [more names...] [options]

Arguments:
    app_name      Name of the application to remove.
        EOF

        opt.separator nil
        opt.separator "Options:"

        opt.on('-D', '--sudo-delete',
               'Delete the app directory using sudo.') do
          options['delete_dir'] = :sudo
        end

        opt.on('-d', '--delete',
               'Delete the app directory.') do
          options['delete_dir'] = true
        end

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

