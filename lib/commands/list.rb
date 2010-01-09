module Sunshine

  module ListCommand

    def self.exec argv, config
    end


    def self.parse_args argv
      options = {}

      opts = OptionParser.new do |opt|
        opt.program_name = File.basename $0
        opt.version = Sunshine::VERSION
        opt.release = nil
        opt.banner = <<-EOF

Usage: #{opt.program_name} list app_name [more names...] [options]

Arguments:
    app_name      Name of an application to list.
        EOF

        opt.separator nil
        opt.separator "Options:"

        opt.on('-i', '--installed',
               'Check if app is installed. See also "sunshine add/rm".') do
          options['return'] = :bool
        end

        opt.on('-s', '--status',
               'Check if an app is running.') do
          options['return'] = :status
        end

        opt.on('-d', '--details',
               'Get details about the deployed apps.') do
          options['return'] = :details
        end

        opt.on('-h', '--health [STATUS]', [:on, :off],
               'Set or get the healthcheck status (on, off).') do |status|
          options['health'] = status
          options['return'] = :health
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
