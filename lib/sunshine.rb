require 'rubygems'
require 'open4'
require 'rainbow'
require 'highline'

require 'settler'
require 'yaml'
require 'erb'
require 'logger'
require 'optparse'
require 'time'

module Sunshine

  VERSION = '0.0.2'

  class Exception < StandardError
    def initialize input=nil, message=nil
      if Exception === input
        message = [message, input.message].compact.join(": ")
        super(message)
        self.set_backtrace(input.backtrace)
      else
        super(input)
      end
    end
  end

  class CmdError < Exception; end

  class SSHCmdError < CmdError
    attr_reader :deploy_server
    def initialize message=nil, deploy_server=nil
      @deploy_server = deploy_server
      super(message)
    end
  end

  class CriticalDeployError < Exception; end
  class FatalDeployError < Exception; end
  class DependencyError < FatalDeployError; end

  require 'sunshine/console'
  require 'sunshine/output'

  require 'sunshine/dependencies'

  require 'sunshine/repo'
  require 'sunshine/repos/svn_repo'

  require 'sunshine/server'
  require 'sunshine/servers/nginx'
  require 'sunshine/servers/unicorn'
  require 'sunshine/servers/rainbows'

  require 'sunshine/crontab'

  require 'sunshine/healthcheck'

  require 'sunshine/deploy_server_dispatcher'
  require 'sunshine/deploy_server'
  require 'sunshine/app'



  def self.console
    @console ||= Sunshine::Console.new
  end

  def self.logger
    log_level = Logger.const_get(@config['level'].upcase)
    @logger ||= Sunshine::Output.new :level => log_level,
      :output => self.console
  end

  ##
  # The default deploy environment to use. Set with the -e option.
  # See App#deploy_env for app specific deploy environments.
  def self.deploy_env
    @config['deploy_env']
  end

  ##
  # Maximum number of deploys (history) to keep on the remote server,
  # 5 by default. Overridden in the ~/.sunshine config file.
  def self.max_deploy_versions
    @config['max_deploy_versions']
  end

  ##
  # Should sunshine ever ask for user input? True by default; overridden with
  # the -a option.
  def self.interactive?
    !@config['auto']
  end

  def self.parse_args argv
    options = {}

    opts = OptionParser.new do |opt|
      opt.program_name = File.basename $0
      opt.version = Sunshine::VERSION
      opt.release = nil
      opt.banner = <<-EOF

Usage: #{opt.program_name} [deploy_file] [options]

Sunshine provides a light api for rack applications deployment. 
      EOF

      opt.separator nil
      opt.separator "[deploy_file]: Load a deploy script or app path."+
        " Defaults to ./Sunshine."

      opt.separator nil
      opt.separator "Deploy-time options:"

      opt.on('-l', '--level LEVEL',
             'Set trace level. Defaults to info.') do |value|
        options['level'] = value
      end

      opt.on('-e', '--env DEPLOY_ENV',
             'Sets the deploy environment. Defaults to development.') do |value|
        options['deploy_env'] = value
      end

      opt.on('-a', '--auto',
             'Non-interactive - automate or fail') do
        options['auto'] = true
      end

    end

    opts.parse! argv

    options
  end

  USER_CONFIG_FILE = File.expand_path("~/.sunshine")

  DEFAULT_CONFIG = {
    'level'               => 'info',
    'deploy_env'          => :development,
    'auto'                => false,
    'max_deploy_versions' => 5
  }

  def self.load_config(filepath=nil)
    YAML.load_file(filepath || USER_CONFIG_FILE)
  end

  def self.run(argv=ARGV)
    unless File.file? USER_CONFIG_FILE
      File.open(USER_CONFIG_FILE, "w+"){|f| f.write DEFAULT_CONFIG.to_yaml}
      puts "Missing config file was created for you: #{USER_CONFIG_FILE}"
      puts DEFAULT_CONFIG.to_yaml
      exit 1
    end

    config = load_config.merge( parse_args(argv) )
    self.setup( config )

    deploy_file = argv.first
    deploy_file = File.join(deploy_file, "Sunshine") if
      deploy_file && File.directory?(deploy_file)
    deploy_file ||= "sunshine"
    puts "Running #{deploy_file}"
    require deploy_file
  end

  def self.setup(new_config={})
    @config ||= DEFAULT_CONFIG
    @config.merge! new_config
  end
end

Sunshine.run
