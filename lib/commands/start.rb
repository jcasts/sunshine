module Sunshine

  module StartCommand

    def self.exec argv, config
      
    end


    def self.parse_args argv
      options = {}

      opts = OptionParser.new do |opt|
        opt.program_name = File.basename $0
        opt.version = Sunshine::VERSION
        opt.release = nil
        opt.banner = <<-EOF

Usage: #{opt.program_name} start app_name [more names...] [options]

Arguments:
    app_name     Name of the application to start.
        EOF

        opt.separator nil
        opt.separator "Options:"

        opt.on('-f', '--force',
               'Restart apps that are running.') do
          options['force'] = true
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

      options
    end
  end
end

