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

      copy_rakefile(config['rakefile'])     if config.has_key? 'rakefile'
      copy_middleware(config['middleware']) if config.has_key? 'middleware'

      return true
    end


    ##
    # Copy template rakefile to specified location.

    def self.copy_rakefile path
      template_rakefile = "#{Sunshine::ROOT}/templates/sunshine/sunshine.rake"

      FileUtils.cp template_rakefile, path

      puts "Copied Sunshine template rakefile to #{path}"
    end


    ##
    # Copy middleware to specified location.

    def self.copy_middleware path
      middleware_dir = "#{Sunshine::ROOT}/templates/sunshine/middleware/."

      FileUtils.cp_r middleware_dir, path

      puts "Copied Sunshine middleware to #{path}"
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
      options = {}

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

   Options:
        EOF

        opt.on('--rakefile [PATH]',
               'Copy the Sunshine template rakefile.') do |path|
          options['rakefile'] = path || File.join(Dir.pwd, "sunshine.rake")
        end

        opt.on('--middleware [PATH]',
               'Copy Sunshine rack middleware files.') do |path|
          options['middleware'] =
            path || File.join(Dir.pwd, ".")
        end

        opt.separator nil
        opt.separator "For more help on sunshine commands, "+
                      "use '#{opt.program_name} COMMAND --help'"
        opt.separator nil
      end


      opts.parse! argv

      if options.empty?
        puts opts
        exit 1
      end

      options
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

        formats = %w{txt yml json}
        opt.on('-f', '--format FORMAT', formats,
               "Set the output format (#{formats.join(', ')})") do |format|
          options['format'] = "#{format}_format".to_sym
        end

        opt.on('-v', '--verbose',
               'Run in verbose mode.') do
          options['verbose'] = true
        end
      end

      opts.parse! argv


      if options['servers']
        options['servers'].map! do |host|
          RemoteShell.new host, :user => options['user']
        end
      else
        options['servers'] = [Sunshine.shell]
      end

      options['format'] ||= :txt_format


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
