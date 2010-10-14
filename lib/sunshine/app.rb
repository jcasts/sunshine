module Sunshine

  ##
  # App objects are the core of Sunshine deployment. The Sunshine paradygm
  # is to construct an app object, and run custom deploy code by passing
  # a block to its deploy method. The following is the simplest way to
  # instantiate an app:
  #
  #   app = Sunshine::App.new :remote_shells => "deploy_server.com"
  #
  # By default, Sunshine will look in the pwd for scm information and will
  # extract the app's name. The default root deploy path is specified by
  # Sunshine.web_directory, in this case: "/srv/http/app_name".
  #
  # More complex setups may look like the following:
  #
  #   someserver = Sunshine::RemoteShell.new "user@someserver.com",
  #                                          :roles => [:web, :app]
  #
  #   myapprepo = Sunshine::SvnRepo.new "svn://my_repo/myapp/tags/release"
  #
  #   app = Sunshine::App.new :name          => 'myapp',
  #                           :repo          => myapprepo,
  #                           :root_path     => '/usr/local/myapp',
  #                           :remote_shells => someserver
  #
  # Note: The instantiation options :repo and :remote_shells support
  # the same data format that their respective initialize methods support.
  # The :remote_shells option also supports arrays of remote shell instance
  # arguments.
  #
  # Once an App is instantiated it can be manipulated in a variety of ways,
  # including deploying it:
  #
  #   app.deploy do |app|
  #
  #     app_server = Sunshine::Rainbows.new app, :port => 3000
  #     web_server = Sunshine::Nginx.new app, :point_to => app_server
  #
  #     app_server.setup
  #     web_server.setup
  #   end
  #
  # The constructor also supports reading multi-env configs fom a yaml file,
  # which can also be the deploy script's DATA, to allow for concise,
  # encapsulated deploy files:
  #
  #   # Load from an explicit yaml file:
  #   Sunshine::App.new "path/to/config.yml"
  #
  #   # Load from the yaml in the script file's DATA:
  #   Sunshine::App.new
  #
  # Yaml files must define settings on a per-environment basis. The default
  # environment will be used as a base for all other environments:
  #
  #   #config.yml:
  #   ---
  #   :default:
  #     :repo:
  #       :type: :svn
  #       :url:  http://subversion/repo/tags/release-001
  #     :remote_shells: dev.myserver.com
  #
  #   qa:
  #     :remote_shells:
  #       - qa1.myserver.com
  #       - qa2.myserver.com
  #
  #   qa_special:
  #     :inherits: qa
  #     :root_path: /path/to/application
  #     :deploy_env: qa
  #
  # By default, App will get the deploy_env value from Sunshine.deploy_env, but
  # it may also be passed in explicitely as an option.

  class App

    ##
    # Initialize and deploy an application in a single step.
    # Takes any arguments supported by the constructor.

    def self.deploy(*args, &block)
      app = new(*args)
      app.deploy(&block)
      app
    end


    attr_reader :name, :repo, :server_apps, :sudo, :deploy_name, :deploy_env
    attr_reader :root_path, :checkout_path, :current_path, :deploys_path
    attr_reader :shared_path, :log_path, :scripts_path
    attr_accessor :remote_checkout

    ##
    # App instantiation can be done in several ways:
    #  App.new instantiation_hash
    #  App.new "path/to/config.yml", optional_extra_hash
    #  App.new #=> will attempt to load ruby's file DATA as yaml
    #
    # Options supported are:
    #
    # :deploy_env:: String - specify the env to deploy with; defaults to
    # Sunshine#deploy_env.
    #
    # :deploy_name:: String - if you want to specify a name for your deploy and
    # checkout directory (affects the checkout_path); defaults to Time.now.to_i.
    #
    # :remote_checkout:: Boolean - when true, will checkout the codebase
    # directly from the deploy servers; defaults to false.
    #
    # :remote_shells:: String|Array|Sunshine::Shell - the shell(s) to use for
    # deployment. Accepts any single instance or array of a Sunshine::Shell
    # type instance or Sunshine::Shell instantiator-friendly arguments.
    #
    # :repo:: Hash|Sunshine::Repo - the scm and repo to use for deployment.
    # Accepts any hash that can be passed to Sunshine::Repo::new_of_type
    # or any Sunshine::Repo object.
    #
    # :root_path:: String - the absolute path the deployed application
    # should live in; defaults to "#{Sunshine.web_directory}/#{@name}".
    #
    # :shell_env:: Hash - environment variables to add to deploy shells.
    #
    # :sudo:: true|false|nil|String - which sudo value should be assigned to
    # deploy shells; defaults to Sunshine#sudo. For more information on using
    # sudo, see the Using Permissions section in README.txt.

    def initialize config_file=Sunshine::DATA, options={}
      options, config_file = config_file, Sunshine::DATA if Hash === config_file


      @deploy_env = options[:deploy_env] || Sunshine.deploy_env

      binder  = Binder.new self
      binder.import_hash options
      binder.forward :deploy_env

      options = config_from_file(config_file, binder.get_binding).merge options


      @repo        = repo_from_config options[:repo]

      @name        = options[:name] || @repo.name

      @deploy_name = options[:deploy_name] || Time.now.to_i.to_s

      @deploy_env = options[:deploy_env] if options[:deploy_env]

      set_deploy_paths options[:root_path]

      @server_apps = server_apps_from_config options[:remote_shells]

      @remote_checkout = options[:remote_checkout] || Sunshine.remote_checkouts?

      self.sudo = options[:sudo] || Sunshine.sudo

      @shell_env = {
        "RACK_ENV"  => @deploy_env.to_s,
        "RAILS_ENV" => @deploy_env.to_s
      }
      shell_env options[:shell_env]

      @post_user_lambdas = []

      @on_sigint = @on_exception = nil
    end


    ##
    # Call a command on specified server apps. Returns an array of responses.
    # Supports any App#find and Shell#call options:
    #   app.call "ls -1", :sudo => true, :host => "web.app.com"
    #   #=> [".\n..\ndir1", ".\n..\ndir1", ".\n..\ndir2"]

    def call cmd, options=nil, &block
      with_server_apps options, :msg => "Running #{cmd}" do |server_app|
        server_app.shell.call cmd, options, &block
      end
    end


    ##
    # Start a persistant connection to app servers.
    # Supports any App#find options.

    def connect options=nil
      Sunshine.logger.info :app, "Connecting..." do
        threaded_each options do |server_app|
          server_app.shell.connect
        end
      end
    end


    ##
    # Check if all server apps are connected and returns a boolean.
    # Supports any App#find options.

    def connected? options=nil
      each options do |server_app|
        return false unless server_app.shell.connected?
      end

      true
    end


    ##
    # Check if any server apps are connected and returns a boolean.
    # Supports any App#find options.

    def any_connected? options=nil
      each options do |server_app|
        return true if server_app.shell.connected?
      end

      false
    end


    ##
    # Disconnect from app servers. Supports any App#find options.

    def disconnect options=nil
      Sunshine.logger.info :app, "Disconnecting..." do
        threaded_each options do |server_app|
          server_app.shell.disconnect
        end
      end
    end


    ##
    # Deploy the application to deploy servers and
    # call user's post-deploy code. Supports any App#find options.
    #
    # If the deploy fails or an exception is raised, it will attempt to
    # run the Sunshine.exception_behavior, which is set to :revert by
    # default. However, this is not true of ssh connection failures.
    #
    # If the deploy is interrupted by a SIGINT, it will attempt to run
    # the Sunshine.sigint_behavior, which is set to :revert by default.
    #
    # The deploy method will stop the former deploy just before
    # symlink and the passed block is run.
    #
    # Once deployment is complete, the deploy method will attempt to
    # run App#start! which will run any start script checked into
    # App#scripts_path, or the start script that will have been generated
    # by using Sunshine server setups.

    def deploy options=nil

      state = {
        :success   => false,
        :stopped   => false,
        :symlinked => false
      }

      Sunshine.logger.info :app, "Beginning #{@name} deploy"

      with_session options do |app|

        interruptable state do
          raise DeployError, "No servers defined for #{@name}" if
            @server_apps.empty?

          make_app_directories
          checkout_codebase

          state[:stopped]   = true if stop
          state[:symlinked] = true if symlink_current_dir

          yield self if block_given?

          run_post_user_lambdas

          build_control_scripts
          build_deploy_info_file
          build_crontab

          register_as_deployed

          state[:success] = true if start! :force => true
        end

        remove_old_deploys if state[:success] rescue
          Sunshine.logger.error :app, "Could not remove old deploys"

        state[:success] &&= deployed?
      end

      Sunshine.logger.info :app, "Finished #{@name} deploy" if state[:success]
      state[:success]
    end


    ##
    # Runs the given block while handling SIGINTs and exceptions
    # according to rules set by Sunshine.sigint_behavior and
    # Sunshine.exception_behavior or with the override hooks
    # App#on_sigint and App#on_exception.

    def interruptable options={}
      interrupt_trap =
        TrapStack.add_trap "Interrupted #{@name}" do
          handle_sigint options
        end

      yield if block_given?

    rescue => e
      Sunshine.logger.error :app, "#{e.class}: #{e.message}" do
        Sunshine.logger.error '>>', e.backtrace.join("\n")
      end

      handle_exception e, options

    ensure
      TrapStack.delete_trap interrupt_trap
    end


    ##
    # Calls the Apps on_sigint hook or the default Sunshine.sigint_behavior.

    def handle_sigint state={}
      return @on_sigint.call(state) if @on_sigint
      handle_interruption Sunshine.sigint_behavior, state
    end


    ##
    # Calls the Apps on_exception hook or the default
    # Sunshine.exception_behavior.

    def handle_exception exception, state={}
      return @on_exception.call(exception, state) if @on_exception
      handle_interruption Sunshine.exception_behavior, state
    end


    ##
    # Set this to define the behavior of SIGINT during a deploy.
    # Defines what to do when an INT signal is received when running
    # a proc through App#interruptable. Used primarily to catch SIGINTs
    # during deploys. Passes the block a hash with the state of the deploy:
    #
    #   app.on_sigint do |deploy_state_hash|
    #     deploy_state_hash
    #     #=> {:stopped => true, :symlinked => true, :success => false}
    #   end

    def on_sigint &block
      @on_sigint = block
    end


    ##
    # Set this to define the behavior of exceptions during a deploy.
    # Defines what to do when an exception is received when running
    # a proc through App#interruptable. Used primarily to catch exceptions
    # during deploys. Passes the block the exception and a hash with the
    # state of the deploy:
    #
    #   app.on_exception do |exception, deploy_state_hash|
    #     # do something...
    #   end

    def on_exception &block
      @on_exception = block
    end


    ##
    # Handles the behavior of a failed or interrupted deploy.
    # Takes a behavior symbol defining how to handle the interruption
    # and a hash representing the state of the deploy when it was
    # interrupted.
    #
    # Supported bahavior symbols are:
    # ::revert:   Revert to previous deploy (default)
    # ::console:  Start an interactive console with the app's binding
    # ::exit:     Stop deploy and exit
    # ::prompt:   Ask what to do
    #
    # The state hash supports the following keys:
    # ::stopped:    Was the previous deploy stopped.
    # ::symlinked:  Was the new deployed symlinked as the current deploy.

    def handle_interruption behavior, state={}
      case behavior

      when :exit
        Sunshine.exit 1, "Error: Deploy of #{@name} failed"

      when :revert
        revert! if state[:symlinked]
        start   if state[:stopped]

      when Sunshine.interactive? && :console
        self.console!

      when Sunshine.interactive? && :prompt
        Sunshine.shell.choose do |menu|
          menu.prompt = "Deploy interrupted:"
          menu.choice(:revert) { handle_interruption :revert,  state }
          menu.choice(:console){ handle_interruption :console, state }
          menu.choice(:exit)   { handle_interruption :exit, state }
        end

      else
        raise DeployError, "Deploy of #{@name} was interrupted."
      end
    end


    ##
    # Symlink current directory to previous checkout and remove
    # the current deploy directory. Supports any App#find options.
    #   app.revert! :role => :web

    def revert! options=nil
      with_server_apps options,
        :msg  => "Reverting to previous deploy.",
        :send => :revert!
    end


    ##
    # Add paths the the shell $PATH env on all app shells.

    def add_shell_paths(*paths)
      path = @shell_env["PATH"] || "$PATH"
      paths << path

      shell_env "PATH" => paths.join(":")
    end


    ##
    # Add a command to the crontab to be generated remotely:
    #   add_to_crontab "reboot", "@reboot /path/to/app/start", :role => :web
    #
    # Note: This method will append jobs to already existing cron jobs for this
    # application and job name, including previous deploys.

    def add_to_crontab name, cronjob, options=nil
      each options do |server_app|
        server_app.crontab[name] << cronjob
      end
    end


    ##
    # Add a command to the crontab to be generated remotely:
    #   cronjob "reboot", "@reboot /path/to/app/start", :role => :web
    #
    # Note: This method will override already existing cron jobs for this
    # application and job name, including previous deploys.

    def cronjob name, cronjob, options=nil
      each options do |server_app|
        server_app.crontab[name] = cronjob
      end
    end


    ##
    # Add a command to a control script to be generated remotely:
    #   add_to_script :start, "do this on start"
    #   add_to_script :start, "start_mail", :role => :mail

    def add_to_script name, script, options=nil
      each options do |server_app|
        server_app.scripts[name] << script
      end
    end


    ##
    # Define lambdas to run right after the user's yield.
    #   app.after_user_script do |app|
    #     ...
    #   end

    def after_user_script &block
      @post_user_lambdas << block
    end


    ##
    # Creates and uploads all control scripts for the application.
    # To add to, or define a control script, see App#add_to_script.

    def build_control_scripts options=nil
      with_server_apps options,
        :msg  => "Building control scripts",
        :send => :build_control_scripts
    end


    ##
    # Writes the crontab on all or selected server apps.
    # To add or remove from the crontab, see App#add_to_crontab and
    # App#remove_cronjob.

    def build_crontab options=nil
      with_server_apps options,
        :msg => "Building the crontab" do |server_app|
        server_app.crontab.write!
      end
    end


    ##
    # Creates a yaml file with deploy information. To add custom information
    # to the info file, use the app's info hash attribute:
    #   app.info[:key] = "some value"

    def build_deploy_info_file options=nil
      with_server_apps options,
        :msg  => "Creating info file",
        :send => :build_deploy_info_file
    end


    ##
    # Parse an erb file and return the newly created string.
    # Default binding is the app's binding.

    def build_erb erb_file, custom_binding=nil
      str = File === erb_file ? erb_file.read : File.read(erb_file)
      ERB.new(str, nil, '-').result(custom_binding || binding)
    end


    ##
    # Starts an IRB console with the instance's binding.

    def console!
      IRB.setup nil unless defined?(IRB::UnrecognizedSwitch)

      workspace = IRB::WorkSpace.new binding
      irb = IRB::Irb.new workspace

      irb.context.irb_name = "sunshine(#{@name})"
      irb.context.prompt_c = "%N:%03n:%i* "
      irb.context.prompt_i = "%N:%03n:%i> "
      irb.context.prompt_n = "%N:%03n:%i> "

      IRB.class_eval do
        @CONF[:IRB_RC].call(irb.context) if @CONF[:IRB_RC]
        @CONF[:MAIN_CONTEXT] = irb.context
      end

      #TODO: remove sigint trap when irb session is closed
      #trap("INT") do
      #  irb.signal_handle
      #end

      catch(:IRB_EXIT) do
        irb.eval_input
      end
    end


    ##
    # Checks out the app's codebase to one or all deploy servers.
    # Supports all App#find options, plus:
    # :copy:: Bool - Checkout locally and rsync; defaults to false.
    # :exclude:: String|Array - Exclude the specified paths during
    # a deploy via copy.

    def checkout_codebase options=nil
      copy_option = options[:copy]          if options
      exclude     = options.delete :exclude if options

      if @remote_checkout && !copy_option
        with_server_apps options,
          :msg  => "Checking out codebase (remotely)",
          :send => [:checkout_repo, @repo]

      else
        Sunshine.logger.info :app, "Checking out codebase (locally)" do

          tmp_path = File.join Sunshine::TMP_DIR, "#{@name}_checkout"
          scm_info = @repo.checkout_to tmp_path

          scm_info[:exclude] =
            [Sunshine.exclude_paths, exclude].flatten.compact

          with_server_apps options,
            :send => [:upload_codebase, tmp_path, scm_info]
        end
      end
    end


    ##
    # Get a hash of deploy information for each server app.
    # Post-deploy only.

    def deploy_details options=nil
      details = {}

      with_server_apps options, :msg => "Getting deploy info..." do |server_app|
        details[server_app.shell.host] = server_app.deploy_details
      end

      details
    end


    ##
    # Check if app has been deployed successfully by checking the name of the
    # deploy on every app server with the instance's deploy name.

    def deployed? options=nil
      with_server_apps options,
        :msg => "Checking deploy", :no_threads => true do |server_app|
        return false unless server_app.deployed?
      end

      true
    end


    ##
    # Iterate over each server app. Supports all App#find options.
    # See Sunshine::ServerApp for more information.

    def each options=nil, &block
      server_apps = find options
      server_apps.each(&block)
    end


    ##
    # Find server apps matching the passed requirements.
    # Returns an array of server apps.
    #   find :user => 'db'
    #   find :host => 'someserver.com'
    #   find :role => :web
    #
    # The find method also supports passing arrays and will match
    # any server app that matches any one condition:
    #   find :user => ['root', 'john']
    #
    # Returns all server apps who's user is either 'root' or 'john'.

    def find query=nil
      return @server_apps if query.nil? || query == :all

      @server_apps.select do |sa|
        next unless [*query[:user]].include? sa.shell.user if query[:user]
        next unless [*query[:host]].include? sa.shell.host if query[:host]

        next unless sa.has_roles?(query[:role], true)      if query[:role]

        true
      end
    end


    ##
    # Decrypt a file using gpg. Supports all App#find options, plus:
    # :output:: str - the path the output file should go to
    # :passphrase:: str - the passphrase gpg should use

    def gpg_decrypt gpg_file, options={}
      options[:passphrase] ||=
        Sunshine.shell.ask("Enter gpg passphrase:") do |q|
        q.echo = false
      end

      with_server_apps options,
        :msg  => "Gpg decrypt: #{gpg_file}",
        :send => [:gpg_decrypt, gpg_file, options]
    end


    ##
    # Install dependencies defined as a Sunshine dependency object:
    #   rake   = Sunshine.dependencies.gem 'rake', :version => '~>0.8'
    #   apache = Sunshine.dependencies.yum 'apache'
    #   app.install_deps rake, apache
    #
    # Deploy servers can also be specified as a dispatcher, array, or single
    # deploy server, by passing standard 'find' options:
    #   postgres = Sunshine.dependencies.yum 'postgresql'
    #   pgserver = Sunshine.dependencies.yum 'postgresql-server'
    #   app.install_deps postgres, pgserver, :role => 'db'
    #
    # If a dependency was already defined in the Sunshine dependency tree,
    # the dependency name may be passed instead of the object:
    #   app.install_deps 'nginx', 'ruby'

    def install_deps(*deps)
      options = Hash === deps[-1] ? deps.delete_at(-1) : {}

      with_server_apps options,
        :msg  => "Installing dependencies: #{deps.map{|d| d.to_s}.join(" ")}",
        :send => [:install_deps, *deps]
    end


    ##
    # Creates the required application directories.
    # Supports all App#find options.

    def make_app_directories options=nil
      with_server_apps options,
        :msg  => "Creating #{@name} directories",
        :send => :make_app_directories
    end


    ##
    # Assign the prefered package manager to all server_apps:
    #   app.prefer_pkg_manager Sunshine::Yum
    #
    # Package managers are typically detected automatically by each
    # individual server_apps.
    # Supports all App#find options.

    def prefer_pkg_manager pkg_manager, options=nil
      with_server_apps options,
        :send => [:pkg_manager=, pkg_manager]
    end


    ##
    # Run a rake task on any or all deploy servers.
    # Supports all App#find options.

    def rake command, options=nil
      with_server_apps options,
        :msg  => "Running Rake task '#{command}'",
        :send => [:rake, command]
    end


    ##
    # Adds the app to the deploy servers deployed-apps list.
    # Supports all App#find options.

    def register_as_deployed options=nil
      with_server_apps options,
        :msg  => "Registering app with deploy servers",
        :send => :register_as_deployed
    end


    ##
    # Remove a cron job from the remote crontabs:
    #   remove_cronjob "reboot", :role => :web
    #   remove_cronjob :all
    #   #=> deletes all cronjobs related to this app
    # Supports all App#find options.

    def remove_cronjob name, options=nil
      with_server_apps options,
        :msg => "Removing cronjob #{name.inspect}" do |server_app|
        if name == :all
          server_app.crontab.clear
        else
          server_app.crontab.delete(name)
        end
      end
    end


    ##
    # Removes old deploys from the checkout_dir
    # based on Sunshine's max_deploy_versions.
    # Supports all App#find options.

    def remove_old_deploys options=nil
      with_server_apps options,
        :msg  => "Removing old deploys (max = #{Sunshine.max_deploy_versions})",
        :send => :remove_old_deploys
    end


    ##
    # Run the restart script of a deployed app on the specified
    # deploy servers.
    # Post-deploy only. Supports all App#find options.

    def restart options=nil
      with_server_apps options,
        :msg  => "Running restart script",
        :send => :restart
    end


    ##
    # Run the restart script of a deployed app on the specified
    # deploy servers. Raises an exception on failure.
    # Post-deploy only. Supports all App#find options.

    def restart! options=nil
      with_server_apps options,
        :msg  => "Running restart script",
        :send => :restart!
    end


    ##
    # Runs bundler on deploy servers. Supports all App#find options.

    def run_bundler options=nil
      with_server_apps options,
        :msg  => "Running Bundler",
        :send => [:run_bundler, options]
    end


    ##
    # Runs GemInstaller on deploy servers. Supports all App#find options.

    def run_geminstaller options=nil
      with_server_apps options,
        :msg  => "Running GemInstaller",
        :send => [:run_geminstaller, options]
    end


    ##
    # Run lambdas that were saved for after the user's script.
    # See #after_user_script.

    def run_post_user_lambdas
      Sunshine.logger.info :app, "Running post deploy lambdas" do
        with_session{ @post_user_lambdas.each{|l| l.call self} }
      end
    end


    ##
    # Run the given script of a deployed app on the specified
    # deploy servers.
    # Post-deploy only. Supports all App#find options.

    def run_script name, options=nil
      with_server_apps options,
        :msg  => "Running #{name} script",
        :send => [:run_script, name, options]
    end


    ##
    # Run the given script of a deployed app on the specified
    # deploy servers. Raises an exception on failure.
    # Post-deploy only. Supports all App#find options.

    def run_script! name, options=nil
      with_server_apps options,
        :msg  => "Running #{name} script",
        :send => [:run_script!, name, options]
    end


    ##
    # Run a sass task on any or all deploy servers.
    # Supports all App#find options.

    def sass *sass_names
      options = sass_names.delete_at(-1) if Hash === sass_names.last

      with_server_apps options,
        :msg  => "Running Sass for #{sass_names.join(' ')}",
        :send => [:sass, *sass_names]
    end


    ##
    # Set and return the remote shell env variables.
    # Also assigns shell environment to the app's deploy servers.
    # Supports all App#find options.

    def shell_env env_hash=nil, options=nil
      env_hash ||= {}

      @shell_env.merge!(env_hash)

      with_server_apps options,
        :no_threads => true,
        :no_session => true,
        :msg => "Shell env: #{@shell_env.inspect}" do |server_app|
        server_app.shell_env.merge!(@shell_env)
      end

      @shell_env.dup
    end


    ##
    # Run the start script of a deployed app on the specified
    # deploy servers.
    # Post-deploy only. Supports all App#find options.

    def start options=nil
      with_server_apps options,
        :msg  => "Running start script",
        :send => [:start, options]
    end


    ##
    # Run the start script of a deployed app on the specified
    # deploy servers. Raises an exception on failure.
    # Post-deploy only. Supports all App#find options.

    def start! options=nil
      with_server_apps options,
        :msg  => "Running start script",
        :send => [:start!, options]
    end


    ##
    # Get a hash of which deploy server apps are :running or :down.
    # Post-deploy only. Supports all App#find options.

    def status options=nil
      statuses = {}

      with_server_apps options, :msg => "Querying app status..." do |server_app|
        statuses[server_app.shell.host] = server_app.status
      end

      statuses
    end


    ##
    # Run the stop script of a deployed app on the specified
    # deploy servers.
    # Post-deploy only. Supports all App#find options.

    def stop options=nil
      with_server_apps options,
        :msg  => "Running stop script",
        :send => :stop
    end


    ##
    # Run the stop script of a deployed app on the specified
    # deploy servers. Raises an exception on failure.
    # Post-deploy only. Supports all App#find options.

    def stop! options=nil
      with_server_apps options,
        :msg  => "Running stop script",
        :send => :stop!
    end


    ##
    # Use sudo on all the app's deploy servers. Set to true/false, or
    # a username to use 'sudo -u'.

    def sudo=(value)
      with_server_apps :all,
        :no_threads => true,
        :no_session => true,
        :msg => "Using sudo = #{value.inspect}" do |server_app|
        server_app.shell.sudo = value
      end

      @sudo = value
    end


    ##
    # Creates a symlink to the app's checkout path.
    # Supports all App#find options.

    def symlink_current_dir options=nil
      with_server_apps options,
        :msg  => "Symlinking #{@checkout_path} -> #{@current_path}",
        :send => :symlink_current_dir
    end


    ##
    # Iterate over all deploy servers but create a thread for each
    # deploy server. Means you can't return from the passed block!
    # Supports all App#find options.

    def threaded_each options=nil, &block
      mutex   = Mutex.new
      threads = []
      error   = nil

      return_val = each(options) do |server_app|

        thread = Thread.new do
          server_app.shell.with_mutex mutex do

            begin
              yield server_app

            rescue => e
              error = e
            end
          end
        end

        threads << thread
      end

      threads.each{|t| t.join }

      raise error if error

      return_val
    end


    ##
    # Execute a block with a specified server app filter:
    #   app.with_filter :role => :cdn do |app|
    #     app.sass 'file1', 'file2', 'file3'
    #     app.rake 'asset:packager:build_all'
    #   end
    # Supports all App#find options.

    def with_filter filter_hash
      old_server_apps, @server_apps = @server_apps, find(filter_hash)

      yield self

    ensure
      @server_apps = old_server_apps
    end


    ##
    # Calls a method for server_apps found with the passed options,
    # and with an optional log message. Will attempt to run the methods in
    # a session to avoid multiple ssh login prompts. Supports all App#find
    # options, plus:
    # :no_threads:: bool - disable threaded execution
    # :no_session:: bool - disable auto session creation
    # :msg:: "some message" - log message
    #
    #   app.with_server_apps :all, :msg => "doing something" do |server_app|
    #     # do something here
    #   end
    #
    #   app.with_server_apps :role => :db, :user => "bob" do |server_app|
    #     # do something here
    #   end
    #
    # Note: App#with_server_apps calls App#with_session. If you do not need
    # or want a server connection you can pass :no_session.

    def with_server_apps search_options, options={}
      options = search_options.merge options if Hash === search_options

      message = options[:msg]
      method  = options[:no_threads] ? :each : :threaded_each
      auto_session = !options[:no_session]

      block = lambda do |*|
        send(method, search_options) do |server_app|

          if block_given?
            yield(server_app)

          elsif options[:send]
            server_app.send(*options[:send])
          end
        end
      end


      msg_block = lambda do |*|
        if message
          Sunshine.logger.info(:app, message, &block)

        else
          block.call
        end
      end

      auto_session ? with_session(&msg_block) : msg_block.call
    end


    ##
    # Runs block ensuring a connection to remote_shells.
    # Connecting and disconnecting will be ignored if a session
    # already exists. Supports all App#find options.
    #
    # Ensures that servers are disconnected after the block is run
    # if servers were not previously connected.

    def with_session options=nil
      with_filter options do
        prev_connection = connected?

        begin
          connect unless prev_connection
          yield self

        ensure
          disconnect unless prev_connection
        end
      end
    end


    private


    ##
    # Set all the app paths based on the root deploy path.

    def set_deploy_paths path
      @root_path     = path || File.join(Sunshine.web_directory, @name)
      @current_path  = "#{@root_path}/current"
      @deploys_path  = "#{@root_path}/deploys"
      @shared_path   = "#{@root_path}/shared"
      @log_path      = "#{@shared_path}/log"
      @checkout_path = "#{@deploys_path}/#{@deploy_name}"
      @scripts_path  = "#{@checkout_path}/sunshine_scripts"
    end


    ##
    # Set the app's deploy servers:
    #   server_apps_from_config "some_server"
    #   #=> [<ServerApp @host="some_server"...>]
    #
    #   server_apps_from_config ["svr1", "svr2", "svr3"]
    #   #=> [<ServerApp @host="svr1">,<ServerApp @host="svr2">, ...]
    #
    #   remote_shells = [["svr1", {:roles => "web db app"}], "svr2", "svr3"]
    #   server_apps_from_config remote_shells
    #   #=> [<ServerApp @host="svr1">,<ServerApp @host="svr2">, ...]

    def server_apps_from_config shells
      shells = [*shells].compact
      shells.map{|shell| ServerApp.new(*[self,*shell]) }
    end


    ##
    # Set the app's repo:
    #   repo_from_config SvnRepo.new("myurl")
    #   repo_from_config :type => :svn, :url => "myurl"

    def repo_from_config repo_def
      case repo_def
      when Sunshine::Repo
        repo_def
      when Hash
        Sunshine::Repo.new_of_type repo_def[:type],
          repo_def[:url], repo_def
      else
        Sunshine::Repo.detect Sunshine::PATH
      end
    end


    ##
    # Load a yml config file, parses it with erb and resolves deploy env
    # inheritance.

    def config_from_file config_file, erb_binding=binding, env=@deploy_env
      return {} unless config_file

      config_data = YAML.load build_erb(config_file, erb_binding)

      load_config_for config_data, env
    end


    ##
    # Loads an app yml config file, gets the default config
    # and the current deploy env and returns a merged config hash.

    def load_config_for config_hash, env
      return {} unless config_hash

      deploy_env_config = (config_hash[env] || {}).dup
      deploy_env_config[:inherits] ||= []
      deploy_env_config[:inherits].unshift(:default) if
        :default != env && config_hash[:default]

      merge_config_inheritance deploy_env_config, config_hash
    end


    ##
    # Recursively merges config hashes based on the value at :inherits

    def merge_config_inheritance main_config, all_configs
      new_config = {}
      parents    = [*main_config[:inherits]].compact

      parents.each do |config_name|
        parent = all_configs[config_name]
        parent = merge_config_inheritance parent, all_configs

        new_config = new_config.merge parent
      end

      new_config.merge main_config # Two merges important for inheritance order
    end
  end
end
