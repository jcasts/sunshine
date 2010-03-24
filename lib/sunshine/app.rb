module Sunshine

  ##
  # App objects are the core of sunshine deployment. The sunshine paradygm
  # is to construct an app object, and run custom deploy code by passing
  # a block to its deploy method:
  #
  #  options = {
  #     :name => 'myapp',
  #     :repo => {:type => :svn, :url => 'svn://blah...'},
  #     :root_path => '/usr/local/myapp',
  #     :remote_shells => ['user@someserver.com']
  #   }
  #
  #   app = Sunshine::App.new(options)
  #
  #   app.deploy do |app|
  #
  #     app_server = Sunshine::Rainbows.new(app)
  #     app_server.restart
  #
  #     Sunshine::Nginx.new(app, :point_to => app_server).restart
  #
  #   end
  #
  # Multiple apps can be defined, and deployed from a single deploy script.
  # The constructor also supports passing a yaml file path:
  #
  #   Sunshine::App.new("path/to/config.yml")
  #
  # Deployment can be expressed more concisely by calling App::deploy:
  #
  #   App.deploy("path/to/config.yml") do |app|
  #     Sunshine::Rainbows.new(app).restart
  #   end

  class App

    ##
    # Initialize and deploy an application.
    # Takes any arguments supported by the constructor.

    def self.deploy(*args, &block)
      app = new(*args)
      app.deploy(&block)
      app
    end


    attr_reader :name, :repo, :server_apps, :sudo
    attr_reader :root_path, :checkout_path, :current_path, :deploys_path
    attr_reader :shared_path, :log_path, :deploy_name, :deploy_env


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

      @server_app_filter = nil

      set_deploy_paths options[:root_path]

      @server_apps = server_apps_from_config options[:remote_shells]

      self.sudo = options[:sudo] || Sunshine.sudo

      @shell_env = {
        "RACK_ENV"  => @deploy_env.to_s,
        "RAILS_ENV" => @deploy_env.to_s
      }
      shell_env options[:shell_env]

      @post_user_lambdas = []
    end


    ##
    # Connect server apps.

    def connect options=nil
      with_server_apps options,
        :msg => "Connecting..." do |server_app|
        server_app.shell.connect
      end
    end


    ##
    # Check if server apps are connected.

    def connected? options=nil
      with_server_apps options, :no_threads => true do |server_app|
        return false unless server_app.shell.connected?
      end

      true
    end


    ##
    # Disconnect server apps.

    def disconnect options=nil
      with_server_apps options,
        :msg => "Disconnecting..." do |server_app|
        server_app.shell.disconnect
      end
    end


    ##
    # Deploy the application to deploy servers and
    # call user's post-deploy code. Supports any App#find options.

    def deploy options=nil
      Sunshine.logger.info :app, "Beginning deploy of #{@name}" do
        connect options
      end

      deploy_trap = Sunshine.add_trap "Reverting deploy of #{@name}" do
        revert! options
      end

      with_filter options do |app|
        make_app_directories
        checkout_codebase
        symlink_current_dir

        yield(self) if block_given?

        run_post_user_lambdas

        setup_healthcheck

        build_control_scripts
        build_deploy_info_file
        build_crontab

        register_as_deployed
        remove_old_deploys
      end

    rescue => e
      message = "#{e.class}: #{e.message}"

      Sunshine.logger.error :app, message do
        Sunshine.logger.error '>>', e.backtrace.join("\n")
        revert!
      end

    ensure
      Sunshine.delete_trap deploy_trap

      Sunshine.logger.info :app, "Ending deploy of #{@name}" do
        disconnect options
      end
    end


    ##
    # Symlink current directory to previous checkout and remove
    # the current deploy directory.

    def revert!(options=nil)
      with_server_apps options,
        :msg  => "Reverting to previous deploy.",
        :send => :revert!
    end


    ##
    # Add paths the the shell $PATH env.

    def add_shell_paths(*paths)
      path = @shell_env["PATH"] || "$PATH"
      paths << path

      shell_env "PATH" => paths.join(":")
    end


    ##
    # Add a command to the crontab to be generated remotely:
    #   add_to_crontab "reboot", "@reboot /path/to/app/start", :role => :web

    def add_to_crontab name, cronjob, options=nil
      with_server_apps options do |server_app|
        server_app.crontab[name] = cronjob
      end
    end


    ##
    # Add a command to a control script to be generated remotely:
    #   add_to_script :start, "do this on start"
    #   add_to_script :start, "start_mail", :role => :mail

    def add_to_script name, script, options=nil
      with_server_apps options do |server_app|
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
    # Checks out the app's codebase to one or all deploy servers.

    def checkout_codebase options=nil
      with_server_apps options,
        :msg  => "Checking out codebase",
        :send => [:checkout_repo, @repo]

    rescue => e
      raise CriticalDeployError, e
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
    # Check if app has been deployed successfully.

    def deployed? options=nil
      with_server_apps options, :no_threads => true do |server_app|
        return false unless server_app.deployed?
      end

      true
    end


    ##
    # Iterate over each server app.

    def each(options=nil, &block)
      server_apps = find(options)
      server_apps.each(&block)
    end


    ##
    # Find server apps matching the passed requirements.
    # Returns an array of server apps.
    #   find :user => 'db'
    #   find :host => 'someserver.com'
    #   find :role => :web

    def find query=nil
      if @server_app_filter
        if Hash === query && Hash === @server_app_filter
          query.merge! @server_app_filter
        else
          query = @server_app_filter
        end
      end

      return @server_apps if query.nil? || query == :all

      @server_apps.select do |sa|
        next unless sa.shell.user == query[:user] if query[:user]
        next unless sa.shell.host == query[:host] if query[:host]

        next unless sa.has_roles?(query[:role])   if query[:role]

        true
      end
    end


    ##
    # Decrypt a file using gpg. Allows all DeployServerDispatcher#find
    # options, plus:
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


    %w{gem yum apt}.each do |dep_type|
      self.class_eval <<-STR, __FILE__, __LINE__ + 1
        ##
        # Install one or more #{dep_type} packages.
        # See Settler::#{dep_type.capitalize}#new for supported options.

        def #{dep_type}_install(*names)
          options = names.last if Hash === names.last
          with_server_apps options,
            :msg  => "Installing #{dep_type} packages",
            :send => [:#{dep_type}_install, *names]
        end
      STR
    end


    ##
    # Gets or sets the healthcheck state. Returns a hash of host/state
    # pairs. State values are :enabled, :disabled, and :down. The method
    # argument can be omitted or take a value of :enable, :disable, or :remove:
    #   app.health
    #   #=> Returns the health status for all server_apps
    #
    #   app.health :role => :web
    #   #=> Returns the status of all server_apps of role :web
    #
    #   app.health :enable
    #   #=> Enables all health checking and returns the status
    #
    #   app.health :disable, :role => :web
    #   #=> Disables health checking for :web server_apps and returns the status

    def health method=nil, options=nil
      valid_methods = [:enable, :disable, :remove]
      options = method if options.nil? && Hash === method

      valid_method = valid_methods.include? method

      message   = "#{method.to_s.capitalize[0..-2]}ing" if valid_method
      message ||= "Getting status of"
      message   = "#{message} healthcheck"

      statuses = {}
      with_server_apps options, :msg => message do |server_app|
        server_app.health.send method if valid_method

        statuses[server_app.shell.host] = server_app.health.status
      end

      statuses
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

    def make_app_directories options=nil
      with_server_apps options,
        :msg  => "Creating #{@name} directories",
        :send => :make_app_directories

    rescue => e
      raise FatalDeployError, e
    end


    ##
    # Assign the prefered package manager to all server_apps:
    #   app.prefer_pkg_manager Settler::Yum
    #
    # Package managers are typically detected automatically by each
    # individual server_apps.

    def prefer_pkg_manager pkg_manager, options=nil
      with_server_apps options,
        :send => [:pkg_manager=, pkg_manager]
    end


    ##
    # Run a rake task on any or all deploy servers.

    def rake command, options=nil
      with_server_apps options,
        :msg  => "Running Rake task '#{command}'",
        :send => [:rake, command]
    end


    ##
    # Adds the app to the deploy servers deployed-apps list.

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

    def remove_old_deploys options=nil
      with_server_apps options,
        :msg  => "Removing old deploys (max = #{Sunshine.max_deploy_versions})",
        :send => :remove_old_deploys
    end


    ##
    # Run the restart script of a deployed app on the specified
    # deploy servers.
    # Post-deploy only.

    def restart options=nil
      with_server_apps options,
        :msg  => "Running restart script",
        :send => :restart
    end


    ##
    # Runs bundler on deploy servers.

    def run_bundler options=nil
      with_server_apps options,
        :msg  => "Running Bundler",
        :send => :run_bundler

    rescue => e
      raise CriticalDeployError, e
    end


    ##
    # Runs GemInstaller on deploy servers.

    def run_geminstaller options=nil
      with_server_apps options,
        :msg  => "Running GemInstaller",
        :send => :run_geminstaller

    rescue => e
      raise CriticalDeployError, e
    end


    ##
    # Run lambdas that were saved for after the user's script.
    # See #after_user_script.

    def run_post_user_lambdas
      @post_user_lambdas.each{|l| l.call self}
    end


    ##
    # Run a sass task on any or all deploy servers.

    def sass *sass_names
      options = sass_names.delete_at(-1) if Hash === sass_names.last

      with_server_apps options,
        :msg  => "Running Sass for #{sass_names.join(' ')}",
        :send => [:sass, *sass_names]
    end


    def setup_healthcheck options=nil
      with_server_apps options,
        :msg => "Setting up healthcheck" do |server_app|
        server_app.health.enable

        health_middleware =
          File.join Sunshine::ROOT, "templates/sunshine/sunshine_health.rb"

        server_app.shell.upload health_middleware, "#{@checkout_path}/."
      end
    end

    ##
    # Set and return the remote shell env variables.
    # Also assigns shell environment to the app's deploy servers.

    def shell_env env_hash=nil
      env_hash ||= {}

      @shell_env.merge!(env_hash)

      with_server_apps :all,
        :msg => "Shell env: #{@shell_env.inspect}" do |server_app|
        server_app.shell_env.merge!(@shell_env)
      end

      @shell_env.dup
    end


    ##
    # Run the start script of a deployed app on the specified
    # deploy servers.
    # Post-deploy only.

    def start options=nil
      with_server_apps options,
        :msg  => "Running start script",
        :send => [:start, options]
    end


    ##
    # Get a hash of which deploy server apps are :running or :down.
    # Post-deploy only.

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
    # Post-deploy only.

    def stop options=nil
      with_server_apps options,
        :msg  => "Running stop script",
        :send => :stop
    end


    ##
    # Use sudo on deploy servers. Set to true/false, or
    # a username to use 'sudo -u'.

    def sudo=(value)
      with_server_apps :all,
        :msg => "Using sudo = #{value.inspect}" do |server_app|
        server_app.shell.sudo = value
      end

      @sudo = value
    end


    ##
    # Creates a symlink to the app's checkout path.

    def symlink_current_dir options=nil
      with_server_apps options,
        :msg  => "Symlinking #{@checkout_path} -> #{@current_path}",
        :send => :symlink_current_dir

    rescue => e
      raise CriticalDeployError, e
    end


    ##
    # Iterate over all deploy servers but create a thread for each
    # deploy server. Means you can't return from the passed block!

    def threaded_each(options=nil, &block)
      mutex   = Mutex.new
      threads = []

      return_val = each(options) do |server_app|

        thread = Thread.new do
          server_app.shell.with_mutex mutex do
            yield server_app
          end
        end

        # We don't want deploy servers to keep doing things if one fails
        thread.abort_on_exception = true

        threads << thread
      end

      threads.each{|t| t.join }

      return_val
    end


    ##
    # Upload common rake tasks from the sunshine lib.
    #   app.upload_tasks
    #     #=> upload all tasks
    #   app.upload_tasks 'app', 'common', :role => :web
    #     #=> upload app and common rake files
    #
    # Allows standard DeployServerDispatcher#find options, plus:
    # :remote_path:: str - the remote absolute path to upload the files to

    def upload_tasks *files
      options = Hash === files.last ? files.last.dup : {}

      options.delete(:remote_path)
      options = :all if options.empty?

      with_server_apps options,
        :msg  => "Uploading tasks: #{files.join(" ")}",
        :send => [:upload_tasks, *files]
    end


    ##
    # Execute a block with a specified server app filter:
    #   app.with_filter :role => :cdn do |app|
    #     app.sass 'file1', 'file2', 'file3'
    #     app.rake 'asset:packager:build_all'
    #   end

    def with_filter filter_hash
      old_filter, @server_app_filter = @server_app_filter, filter_hash

      yield self

      @server_app_filter = old_filter
    end


    ##
    # Calls a method for server_apps found with the passed options,
    # and with an optional log message. Supports all App#find
    # options, plus:
    # :no_threads:: bool - disable threaded execution
    # :msg:: "some message" - log message
    #
    #   app.with_server_apps :all, :msg => "doing something" do |server_app|
    #     # do something here
    #   end
    #
    #   app.with_server_apps :role => :db, :user => "bob" do |server_app|
    #     # do something here
    #   end

    def with_server_apps search_options, options={}
      options = search_options.merge options if Hash === search_options

      message = options[:msg]
      method  = options[:no_threads] ? :each : :threaded_each

      block = lambda do
        send(method, search_options) do |server_app|

          if block_given?
            yield(server_app)

          elsif options[:send]
            server_app.send(*options[:send])
          end
        end
      end


      if message
        Sunshine.logger.info(:app, message, &block)

      else
        block.call
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
    end


    ##
    # Set the app's deploy servers:
    #   server_apps_from_config "some_server"
    #   #=> [<ServerApp @host="some_server"...>]
    #
    #   server_apps_from_config ["svr1", "svr2", "svr3"]
    #   #=> [<ServerApp @host="svr1">,<ServerApp @host="svr2">, ...]
    #
    #   d_servers = [["svr1", {:roles => "web db app"}], "svr2", "svr3"]
    #   server_apps_from_config d_servers
    #   #=> [<ServerApp @host="svr1">,<ServerApp @host="svr2">, ...]

    def server_apps_from_config d_servers
      d_servers = [*d_servers].compact
      d_servers.map{|ds| ServerApp.new(*[self,*ds]) }
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
