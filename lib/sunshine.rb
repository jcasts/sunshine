require 'rubygems'
require 'open4'
require 'rainbow'
require 'highline'
require 'json'

require 'yaml'
require 'erb'
require 'logger'
require 'optparse'
require 'time'
require 'fileutils'
require 'tmpdir'
require 'irb'


# Turn off EOF tracking to be able to prompt on deploy exceptions.
HighLine.track_eof = false


##
# Main module, used for configuration and running commands.

module Sunshine

  ##
  # Sunshine version.
  VERSION = '1.2.1'

  ##
  # Path to the list of installed sunshine apps.
  APP_LIST_PATH = "~/.sunshine_list"

  ##
  # Commands supported by Sunshine.
  COMMANDS = %w{add list restart rm run script start stop}

  ##
  # File DATA from Sunshine run files.
  DATA = defined?(::DATA) ? ::DATA : nil

  ##
  # Default configuration.
  DEFAULT_CONFIG = {
    'interactive'         => true,
    'auto_dependencies'   => true,
    'deploy_env'          => :development,
    'exception_behavior'  => :revert,
    'exclude_paths'       => [],
    'level'               => 'info',
    'max_deploy_versions' => 5,
    'remote_checkouts'    => false,
    'timeout'             => 300,
    'sigint_behavior'     => :revert,
    'web_directory'       => '/srv/http'
  }

  ##
  # Path where Sunshine assumes repo information can be found if missing.
  PATH = Dir.getwd

  ##
  # Root directory of the Sunshine gem.
  ROOT = File.expand_path File.join(File.dirname(__FILE__), "..")

  ##
  # Default Sunshine config file
  USER_CONFIG_FILE = File.expand_path("~/.sunshine")

  ##
  # Temp directory used by various sunshine classes
  # for uploads, checkouts, etc...
  TMP_DIR = File.join Dir.tmpdir, "sunshine_#{$$}"
  FileUtils.mkdir_p TMP_DIR


  ##
  # Returns the Sunshine config hash.

  def self.config
    @config ||= DEFAULT_CONFIG.dup
  end


  ##
  # The default deploy environment to use. Set with the -e option.
  # See App#deploy_env for app specific deploy environments.

  def self.deploy_env
    @config['deploy_env'].to_s
  end


  ##
  # Automatically install dependencies as needed. Defaults to true.
  # Overridden in the ~/.sunshine config file or at setup time.

  def self.auto_dependencies?
    @config['auto_dependencies']
  end


  ##
  # Returns the main Sunshine dependencies library. If passed a block,
  # evaluates the block within the dependency lib instance:
  #
  #   Sunshine.dependencies do
  #     yum 'new_dep'
  #     gem 'commander'
  #   end

  def self.dependencies(&block)
    @dependency_lib ||= DependencyLib.new
    @dependency_lib.instance_eval(&block) if block_given?
    @dependency_lib
  end


  ##
  # Defines what to do when deploy raises an exception.
  # Supported values are:
  #   ::revert:  Revert to the previous deploy.
  #   ::console: Start an interactive ruby shell within the app's context.
  #   ::exit:    Stop deploy and exit, leaving deploy in unfinished state.
  #   ::prompt:  Ask what to do.
  # Defaults to :revert. Overridden in the config.

  def self.exception_behavior
    @config['exception_behavior']
  end


  ##
  # Array of paths or globs that should be excluded from the checkout.
  # Does not work with remote_checkouts enabled.

  def self.exclude_paths
    @config['exclude_paths']
  end


  ##
  # Should sunshine ever ask for user input? True by default.
  # Overridden in the config or with the -a option.

  def self.interactive?
    @config['interactive']
  end


  ##
  # Handles all output for sunshine. See Sunshine::Output.

  def self.logger
    @logger
  end


  ##
  # Maximum number of deploys (history) to keep on the remote server,
  # 5 by default. Overridden in the config.

  def self.max_deploy_versions
    @config['max_deploy_versions']
  end


  ##
  # Check if the codebase should be checked out remotely, or checked out
  # locally and rsynced up. Overridden in the config.

  def self.remote_checkouts?
    @config['remote_checkouts']
  end


  ##
  # Handles input/output to the shell. See Sunshine::Shell.

  def self.shell
    @shell ||= Sunshine::Shell.new
  end


  ##
  # Defines what to do when sigint is sent during deploys.
  # Supported values are:
  #   ::revert:  Revert to the previous deploy.
  #   ::console: Start an interactive ruby shell within the app's context.
  #   ::exit:    Stop deploy and exit, leaving deploy in unfinished state.
  #   ::prompt:  Ask what to do.
  # Defaults to :revert. Overridden in the config.

  def self.sigint_behavior
    @config['sigint_behavior']
  end


  ##
  # How long to wait on a command to finish when no output is received.
  # Defaults to 300 (seconds). Overridden in the config.
  # Set to false to disable timeout.

  def self.timeout
    @config['timeout']
  end


  ##
  # Check if trace log should be output at all.
  # This value can be assigned by default in ~/.sunshine
  # or switched off with the run command's --no-trace option.
  # Defaults to true.

  def self.trace?
    @config['trace']
  end


  ##
  # The default directory where apps should be deployed to:
  # '/var/www' by default. Overridden in the config.
  # See also App#deploy_path.

  def self.web_directory
    @config['web_directory']
  end



  ##
  # Global value of sudo to use. Returns true, nil, or a username.
  # This value can be assigned by default in ~/.sunshine
  # or with the --sudo [username] option. Defaults to nil.

  def self.sudo
    @config['sudo']
  end


  ##
  # Cleanup after Sunshine has run, remove temp dirs, etc...

  def self.cleanup
    FileUtils.rm_rf TMP_DIR if Dir.glob("#{TMP_DIR}/*").empty?
  end


  ##
  # Loads a yaml config file to run setup with.

  def self.load_config_file conf
    setup YAML.load_file(conf)
  end


  ##
  # Loads the USER_CONFIG_FILE and runs setup. Creates the default
  # config file and exits if not present.

  def self.load_user_config
    unless File.file? USER_CONFIG_FILE
      File.open(USER_CONFIG_FILE, "w+"){|f| f.write DEFAULT_CONFIG.to_yaml}

      msg = "Missing config file was created for you: #{USER_CONFIG_FILE}\n\n"
      msg << DEFAULT_CONFIG.to_yaml

      self.exit 1, msg
    end

    load_config_file USER_CONFIG_FILE

    @config['deploy_env'] =
      ENV['DEPLOY_ENV'] ||
      ENV['env']        ||
      ENV['RACK_ENV']   ||
      ENV['RAILS_ENV']  ||
      @config['deploy_env']

    @config
  end


  ##
  # Loads an array of libraries or gems.

  def self.require_libs(*libs)
    libs.compact.each{|lib| require lib }
  end


  ##
  # Setup Sunshine with a custom config:
  #   Sunshine.setup 'level' => 'debug', 'deploy_env' => :production

  def self.setup new_config={}, reset=false
    @config = DEFAULT_CONFIG.dup if reset

    TrapStack.trap_signal :INT do |msg|
      $stderr << "\n\n"
      logger.indent = 0
      logger.fatal :INT, "Caught INT signal!"
      logger.info :INT, msg
    end

    TrapStack.add_trap "Disconnecting all remote shells." do
      RemoteShell.disconnect_all
    end


    require_libs(*new_config['require'])

    config.merge! new_config

    log_level = Logger.const_get config['level'].upcase rescue Logger::INFO
    @logger   = Sunshine::Output.new :level => log_level

    config
  end


  ##
  # Run Sunshine with the passed argv and exits with appropriate exitcode.
  #   run %w{run my_script.rb -l debug}
  #   run %w{list -d}
  #   run %w{--rakefile}

  def self.run argv=ARGV
    command = find_command argv.first
    argv.shift if command

    command ||= DefaultCommand

    setup command.parse_args(argv)

    result = command.exec argv, config

    self.exit(*result)
  end


  ##
  # Find the sunshine command to run based on the passed name.
  # Handles partial command names if they can be uniquely mapped to a command.
  #   find_command "ru" #=> Sunshine::RunCommand
  #   find_command "l" #=> Sunshine::ListCommand
  #   find_command "zzz" #=> nil

  def self.find_command name
    commands = COMMANDS.select{|c| c =~ /^#{name}/}
    return unless commands.length == 1 && commands.first

    Sunshine.const_get "#{commands.first.capitalize}Command"
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
    self.cleanup

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


  require 'sunshine/exceptions'
  require 'sunshine/trap_stack'

  require 'sunshine/shell'
  require 'sunshine/remote_shell'

  require 'sunshine/output'

  require 'sunshine/binder'

  require 'sunshine/server_app'
  require 'sunshine/app'

  require 'sunshine/dependency_lib'
  require 'sunshine/package_managers/dependency'
  require 'sunshine/package_managers/apt'
  require 'sunshine/package_managers/yum'
  require 'sunshine/package_managers/gem'

  require 'sunshine/repo'
  require 'sunshine/repos/svn_repo'
  require 'sunshine/repos/git_repo'
  require 'sunshine/repos/rsync_repo'

  require 'sunshine/daemon'
  require 'sunshine/daemons/server_cluster'
  require 'sunshine/daemons/server'
  require 'sunshine/daemons/apache'
  require 'sunshine/daemons/nginx'
  require 'sunshine/daemons/thin'
  require 'sunshine/daemons/unicorn'
  require 'sunshine/daemons/rainbows'
  require 'sunshine/daemons/mongrel_rails'
  require 'sunshine/daemons/ar_sendmail'
  require 'sunshine/daemons/delayed_job'

  require 'sunshine/crontab'

  require 'sunshine/healthcheck'

  require 'commands/default'
  require 'commands/list'
  require 'commands/add'
  require 'commands/run'
  require 'commands/restart'
  require 'commands/rm'
  require 'commands/script'
  require 'commands/start'
  require 'commands/stop'
end

Sunshine.load_user_config

require 'sunshine/dependencies'
