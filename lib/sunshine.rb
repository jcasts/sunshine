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

  require 'commands/add'
  require 'commands/default'
  require 'commands/deploy'
  require 'commands/list'
  require 'commands/restart'
  require 'commands/rm'
  require 'commands/start'
  require 'commands/stop'


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

    command = Sunshine.const_get("#{command_name.capitalize}Command")

    config = load_config.merge command.parse_args(argv)
    self.setup config

    command.exec argv, config
  end


  def self.find_command name
    commands = COMMANDS.select{|c| c =~ /^#{name}/}
    commands.length == 1 && commands.first
  end
end

