module Sunshine

  ##
  # Default sunshine behavior when no command is passed. Outputs help.

  class DefaultCommand

    ##
    # Takes an array and a hash, runs the command and returns:
    #   true: success
    #   false: failed
    #   exitcode:
    #     code == 0: success
    #     code != 0: failed
    # and optionally an accompanying message.

    def self.exec argv, config
      return false
    end


    ##
    # Base option parser constructor used by all commands.

    def self.opt_parser options=nil
      OptionParser.new do |opt|
        opt.program_name = File.basename $0
        opt.version = Sunshine::VERSION
        opt.release = nil

        yield opt if block_given?

        opt.on('-S', '--sudo [USER]',
               'Run remote commands using sudo or sudo -u USER.') do |value|
          options['sudo'] = value || true
        end if options
      end
    end


    ##
    # Returns the main sunshine help when no arguments are passed.

    def self.parse_args argv
      opts = opt_parser do |opt|
        opt.banner = <<-EOF

Sunshine is an object oriented deploy tool for rack applications. 

  Usage:
    #{opt.program_name} -h/--help
    #{opt.program_name} -v/--version
    #{opt.program_name} command [arguments...] [options...]

  Examples:
    #{opt.program_name} deploy deploy_script.rb
    #{opt.program_name} restart myapp -r user@server.com,user@host.com
    #{opt.program_name} list myapp myotherapp --health -r user@server.com
    #{opt.program_name} list myapp --status

  Commands:
    add       Register an app with #{opt.program_name}
    deploy    Run a deploy script
    list      Display deployed apps
    restart   Restart a deployed app
    rm        Unregister an app with #{opt.program_name}
    start     Start a deployed app
    stop      Stop a deployed app

  For more help on sunshine commands, use '#{opt.program_name} COMMAND --help'

        EOF
      end

      opts.parse! argv
      puts opts
      exit 1
    end


    ##
    # Parse arguments for a command that acts remotely.

    def self.parse_remote_args argv, &block
      options = {}

      opts = opt_parser(options) do |opt|
        opt.separator nil
        opt.separator "Options:"

        yield(opt, options) if block_given?

        opt.on('-u', '--user USER',
               'User to use for ssh login. Use with -r.') do |value|
          options['user'] = value
        end

        opt.on('-r', '--remote server1,server2', Array,
               'Run on one or more remote servers.') do |servers|
          options['servers'] = servers
        end

        opt.on('-v', '--verbose',
               'Run in verbose mode.') do
          options['verbose'] = true
        end
      end

      opts.parse! argv


      if options['servers']
        options['servers'].map! do |host|
          DeployServer.new host, :user => options['user']
        end
        options['servers'] = DeployServerDispatcher.new(*options['servers'])
      else
        options['servers'] = [Sunshine.console]
      end


      if options['sudo']
        options['servers'].each do |ds|
          ds.sudo = options['sudo']
        end
      end

      options
    end


    ##
    # Build a Sunshine command response

    def self.build_response status, data
      {'status' => status, 'data' => data}.to_yaml
    end
  end
end
