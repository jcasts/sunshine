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

  require 'sunshine/exceptions'

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



  ##
  # Handles input/output to the shell

  def self.console
    @console ||= Sunshine::Console.new
  end


  ##
  # The logger for sunshine.

  def self.logger
    log_level = Logger.const_get(@config['level'].upcase)
    @logger ||= Sunshine::Output.new :level => log_level,
      :output => self.console
  end


  ##
  # Check if trace log should be output at all

  def self.trace?
    @config['trace']
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

  APP_LIST_PATH = "~/.sunshine_list"
  READ_LIST_CMD = "test -f #{Sunshine::APP_LIST_PATH} && "+
      "cat #{APP_LIST_PATH} || echo ''"

  COMMANDS = %w{add deploy list restart rm start stop}

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


  ##
  # Setup sunshine with a custom config:
  #   Sunshine.setup 'level' => 'debug', 'deploy_env' => :production

  def self.setup new_config={}
    @config ||= DEFAULT_CONFIG
    @config.merge! new_config
  end


  def self.run argv=ARGV
    unless File.file? USER_CONFIG_FILE
      File.open(USER_CONFIG_FILE, "w+"){|f| f.write DEFAULT_CONFIG.to_yaml}

      puts "Missing config file was created for you: #{USER_CONFIG_FILE}"
      puts DEFAULT_CONFIG.to_yaml

      exit 1
    end

    command_name = find_command argv.first
    argv.shift if command_name
    command_name ||= "default"

    require "commands/#{command_name}"
    command = Sunshine.const_get("#{command_name.capitalize}Command")

    config = load_config.merge command.parse_args(argv)
    self.setup config

    command.exec argv, config
  end


  def self.find_command name
    commands = COMMANDS.select{|c| c =~ /^#{name}/}
    commands.length == 1 && commands.first
  end


  ##
  # Register an app with sunshine.
  #   -r, --remote [USER@]SERVER   Run on a remote server
  # The server can also be specified at the beginning of the path.
  # Multiple servers can be used.
  #   sunshine add [[user@]server:]/path/to/app/root [more paths...] [opts]
  #   sunshine add /path/to/app/root [more paths...] -r server1,server2


  ##
  # Run a deploy script:
  #   -e, --env ENV             Deploy enviroment
  #   -l, --level LVL           Set trace level, defaults to info
  #   sunshine deploy [deploy_script.rb] [opts]


  ##
  # List deployed sunshine apps and/or affect a list of deployed apps.
  #   -i, --installed              Return true/false
  #   -s, --status                 Get the current app status
  #   -d, --details                Get details about the app's deploy
  #   -h, --health [on/off]        Get or set the app's healthcheck
  #   -r, --remote [USER@]SERVER   Run on a remote server
  #   sunshine list [app names] [opts]


  ##
  # Restart one or more deployed sunshine apps.
  #   -A, --all                    Affect all deployed apps
  #   -r, --remote [USER@]SERVER   Run on a remote server
  #   sunshine restart app [more apps]


  ##
  # Unregister an app with sunshine.
  #   -D, --delete                 Removes the app directory as well
  #   -r, --remote [USER@]SERVER   Run on a remote server
  #   sunshine rm [[user@]server:]app [more apps...] [opts]
  #   sunshine rm app [more apps...] -r server1,server2


  ##
  # Start one or more deployed sunshine apps.
  #   -A, --all                    Affect all deployed apps
  #   -f, --force                  Restart apps that are running
  #   -r, --remote [USER@]SERVER   Run on a remote server
  #   sunshine start app [more apps]


  ##
  # Stop one or more deployed sunshine apps.
  #   -A, --all                    Affect all deployed apps
  #   -r, --remote [USER@]SERVER   Run on a remote server
  #   sunshine restart app [more apps]

end

