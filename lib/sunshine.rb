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

##
# Sunshine is an object oriented deploy tool for rack applications.
#
# Writing a Sunshine config script is easy:
#
#   options = {
#     :name => 'myapp',
#     :repo => {:type => :svn, :url => 'svn://blah...'},
#     :deploy_path => '/usr/local/myapp',
#     :deploy_servers => ['user@someserver.com']
#   }
#
#   Sunshine::App.deploy(options) do |app|
#     sqlite = Sunshine::Dependencies.yum 'sqlite3'
#     sqlgem = Sunshine::Dependencies.gem 'sqlite3'
#
#     app.install_deps sqlite, sqlgem
#
#     app.install_gems    # Install gems defined by bundler or geminstaller conf
#
#     app.rake "db:migrate"
#
#     app_server = Sunshine::Rainbows.new(app)
#     app_server.restart
#
#     Sunshine::Nginx.new(app, :point_to => app_server).restart
#
#   end
#
# The App::deploy and App::new methods also support passing
# a path to a yaml file:
#
#   app = Sunshine::App.new("path/to/config.yml")
#   app.deploy!{|app| Sunshine::Rainbows.new(app).restart }
#
#
# Command line execution:
#
#   Usage:
#     sunshine -h/--help
#     sunshine -v/--version
#     sunshine command [arguments...] [options...]
#
#   Examples:
#     sunshine deploy deploy_script.rb
#     sunshine restart myapp -r user@server.com,user@host.com
#     sunshine list myapp myotherapp --health -r user@server.com
#     sunshine list myapp --status
#
#   Commands:
#     add       Register an app with sunshine
#     deploy    Run a deploy script
#     list      Display deployed apps
#     restart   Restart a deployed app
#     rm        Unregister an app with sunshine
#     start     Start a deployed app
#     stop      Stop a deployed app
#
#    For more help on sunshine commands, use 'sunshine COMMAND --help'

module Sunshine

  VERSION = '0.0.3'

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
  # Handles input/output to the shell. See Sunshine::Console.

  def self.console
    @console ||= Sunshine::Console.new
  end

  ##
  # The default deploy environment to use. Set with the -e option.
  # See App#deploy_env for app specific deploy environments.

  def self.deploy_env
    @config['deploy_env']
  end


  ##
  # Should sunshine ever ask for user input? True by default; overridden with
  # the -a option.

  def self.interactive?
    !@config['auto']
  end


  ##
  # Handles all output for sunshine. See Sunshine::Output.

  def self.output
    log_level = Logger.const_get(@config['level'].upcase)
    @logger ||= Sunshine::Output.new :level => log_level,
      :output => self.console
  end

  def self.logger
    self.output
  end



  ##
  # Maximum number of deploys (history) to keep on the remote server,
  # 5 by default. Overridden in the ~/.sunshine config file.

  def self.max_deploy_versions
    @config['max_deploy_versions']
  end


  ##
  # Check if trace log should be output at all.

  def self.trace?
    @config['trace']
  end


  ##
  # Path to the list of installed sunshine apps.
  APP_LIST_PATH = "~/.sunshine_list"

  READ_LIST_CMD = "test -f #{Sunshine::APP_LIST_PATH} && "+
      "cat #{APP_LIST_PATH} || echo ''"

  ##
  # Commands supported by Sunshine
  COMMANDS = %w{add deploy list restart rm start stop}

  ##
  # Default Sunshine config file
  USER_CONFIG_FILE = File.expand_path("~/.sunshine")

  ##
  # Default configuration
  DEFAULT_CONFIG = {
    'level'               => 'info',
    'deploy_env'          => :development,
    'auto'                => false,
    'max_deploy_versions' => 5
  }


  ##
  # Setup sunshine with a custom config:
  #   Sunshine.setup 'level' => 'debug', 'deploy_env' => :production

  def self.setup new_config={}, reset=false
    @config = DEFAULT_CONFIG.dup if !defined?(@config) || reset
    @config.merge! new_config
    @config
  end


  ##
  # Run sunshine with the passed argv and exits with appropriate exitcode.
  #   run %w{deploy my_script.rb -l debug}
  #   run %w{list -d}

  def self.run argv=ARGV
    unless File.file? USER_CONFIG_FILE
      File.open(USER_CONFIG_FILE, "w+"){|f| f.write DEFAULT_CONFIG.to_yaml}

      msg = "Missing config file was created for you: #{USER_CONFIG_FILE}\n\n"
      msg << DEFAULT_CONFIG.to_yaml

      self.exit 1, msg
    end

    command_name = find_command argv.first
    argv.shift if command_name
    command_name ||= "default"

    command = Sunshine.const_get("#{command_name.capitalize}Command")

    config = YAML.load_file USER_CONFIG_FILE
    config.merge! command.parse_args(argv)

    self.setup config, true

    result = command.exec argv, config
    self.exit(*result)
  end


  ##
  # Find the sunshine command to run based on the passed name.
  # Handles partial command names if they can be uniquely mapped to a command.
  #   find_command "dep" #=> "deploy"
  #   find_command "zzz" #=> false

  def self.find_command name
    commands = COMMANDS.select{|c| c =~ /^#{name}/}
    commands.length == 1 && commands.first
  end


  ##
  # Exits sunshine process and returns the appropriate exit code
  #   exit 0, "ok"
  #   exit false, "ok"
  #     # both output: stdout >> ok - exitcode 0
  #   exit 1, "oh noes"
  #   exit true, "oh noes"
  #     # both output: stderr >> oh noes - exitcode 1

  def self.exit status, msg=nil
    status = case status
    when true
      0
    when false
      1
    when Integer
      status
    else
      status.to_i
    end

    output = status == 0 ? $stdout : $stderr

    output << "#{msg}\n" if !msg.nil?

    Kernel.exit status
  end
end

