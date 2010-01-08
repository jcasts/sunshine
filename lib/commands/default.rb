module Sunshine
  module DefaultCommand

    def self.exec(argv)
      exit 1
    end


    def self.parse_args argv
      options = {}

      opts = OptionParser.new do |opt|
        opt.program_name = File.basename $0
        opt.version = Sunshine::VERSION
        opt.release = nil
        opt.banner = <<-EOF

Sunshine is an object oriented deploy tool for rack applications. 

  Usage:
    #{opt.program_name} -h/--help
    #{opt.program_name} -v/--version
    #{opt.program_name} command [arguments...] [options...]

  Examples:
    #{opt.program_name} deploy deploy_script.rb
    #{opt.program_name} restart user@server.com:myapp
    #{opt.program_name} list myapp myotherapp --health on -r user@server.com
    #{opt.program_name} list user@server.com:myapp --status

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
  end
end
