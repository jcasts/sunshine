module Sunshine

  ##
  # App objects are the core of sunshine deployment. The sunshine paradygm
  # is to construct an app object, and run custom deploy code by passing
  # a block to its deploy method:
  #
  #  options = {
  #     :name => 'myapp',
  #     :repo => {:type => :svn, :url => 'svn://blah...'},
  #     :deploy_path => '/usr/local/myapp',
  #     :deploy_servers => ['user@someserver.com']
  #   }
  #
  #   app = Sunshine::App.new(options)
  #
  #   app.deploy! do |app|
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
      app.deploy!(&block)
      app
    end


    attr_reader :name, :repo, :deploy_servers, :crontab, :health, :sudo
    attr_reader :deploy_path, :checkout_path, :current_path
    attr_reader :deploys_dir, :shared_path, :log_path, :deploy_name
    attr_accessor :deploy_env


    def initialize(*args)
      config_file    = args.shift unless Hash === args.first
      config_file  ||= Sunshine::DATA if defined?(Sunshine::DATA)

      options = args.empty? ? {} : args.first.dup
      options[:deploy_env] ||= Sunshine.deploy_env

      options = merge_config_file config_file, options


      set_repo options[:repo]

      @name        = options[:name] || @repo.name
      @crontab     = Crontab.new @name
      @deploy_env  = options[:deploy_env].to_s

      @deploy_name = options[:deploy_name] || Time.now.to_i.to_s

      set_deploy_paths options[:deploy_path]

      set_deploy_servers options[:deploy_servers]

      self.sudo = options[:sudo] || Sunshine.sudo

      @health = Healthcheck.new @shared_path, @deploy_servers

      @shell_env = {
        "RACK_ENV"  => @deploy_env.to_s,
        "RAILS_ENV" => @deploy_env.to_s
      }
      shell_env options[:shell_env]

      @post_user_lambdas = []
    end


    ##
    # Deploy the application to deploy servers and
    # call user's post-deploy code.

    def deploy!(&block)
      @deploy_successful = false

      Sunshine.logger.info :app, "Beginning deploy of #{@name}" do
        @deploy_servers.connect
      end

      make_app_directories
      checkout_codebase
      symlink_current_dir

      yield(self) if block_given?

      run_post_user_lambdas

      build_control_scripts
      build_deploy_info_file
      @health.enable

      register_as_deployed
      remove_old_deploys

      @deploy_successful = true

    rescue DeployError => e
      handle_deploy_error e

    ensure
      Sunshine.logger.info :app, "Ending deploy of #{@name}" do
        @deploy_servers.disconnect
      end
    end


    ##
    # Figure out what to do based on what kind of deploy error was received.

    def handle_deploy_error e
      message = "#{e.class}: #{e.message}"
      log_method = FatalDeployError === e ? :fatal : :error

      Sunshine.logger.send(log_method, :app, message) do
        Sunshine.logger.error '>>', e.backtrace.join("\n")

        revert! if CriticalDeployError === e
      end
    end


    ##
    # Symlink current directory to previous checkout and remove
    # the current deploy directory.

    def revert!
      with_server_apps :all,
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
    # Add a command to a control script to be generated on deploy servers:
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

    def build_control_scripts
      with_server_apps :all,
        :msg  => "Building control scripts",
        :send => :build_control_scripts
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

    def build_erb(erb_file, custom_binding=nil)
      str = File.read(erb_file)
      ERB.new(str, nil, '-').result(custom_binding || binding)
    end


    ##
    # Checks out the app's codebase to one or all deploy servers.

    def checkout_codebase options=nil
      with_server_apps options,
        :msg  => "Checking out codebase",
        :send => :checkout_codebase

    rescue => e
      raise CriticalDeployError, e
    end


    ##
    # Check if app has been deployed successfully.

    def deployed?
      @deploy_successful
    end


    ##
    # An array of all directories used by the app.
    # Does not include symlinked directories

    def directories
      [@deploy_path, @deploys_dir, @shared_path, @log_path, @checkout_path]
    end


    ##
    # Decrypt a file using gpg. Allows all DeployServerDispatcher#find
    # options, plus:
    # :output:: str - the path the output file should go to
    # :passphrase:: str - the passphrase gpg should use

    def gpg_decrypt gpg_file, options={}
      options[:passphrase] ||=
        Sunshine.console.ask("Enter gpg passphrase:") do |q|
        q.echo = false
      end

      with_server_apps options,
        :msg  => "Gpg decrypt: #{gpg_file}",
        :send => [:gpg_decrypt, gpg_file, options]
    end


    ##
    # Install dependencies defined as a Sunshine dependency object:
    #   rake   = Sunshine::Dependencies.gem 'rake', :version => '~>0.8'
    #   apache = Sunshine::Dependencies.yum 'apache'
    #   app.install_deps rake, apache
    #
    # Deploy servers can also be specified as a dispatcher, array, or single
    # deploy server, by passing standard 'find' options:
    #   postgres = Sunshine::Dependencies.yum 'postgresql'
    #   pgserver = Sunshine::Dependencies.yum 'postgresql-server'
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
    # Install gem dependencies defined by the app's checked-in
    # bundler or geminstaller config.

    def install_gems options=nil
      with_server_apps options,
        :msg  => "Installing gems",
        :send => :install_gems

    rescue => e
      raise CriticalDeployError, e
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
    # Run a rake task on any or all deploy servers.

    def rake command, options=nil
      with_server_apps options,
        :msg  => "Running Rake task '#{command}'",
        :send => [:rake, command]
    end


    ##
    # Adds the app to the deploy servers deployed-apps list

    def register_as_deployed options=nil
      with_server_apps options,
        :msg  => "Registering app with deploy servers",
        :send => :register_as_deployed
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


    ##
    # Set and return the remote shell env variables.
    # Also assigns shell environment to the app's deploy servers.

    def shell_env env_hash=nil
      env_hash ||= {}

      @shell_env.merge!(env_hash)

      with_server_apps :all,
        :msg => "Shell env: #{@shell_env.inspect}" do |server_app|
        server_app.env.merge!(@shell_env)
      end

      @shell_env.dup
    end


    ##
    # Use sudo on deploy servers. Set to true/false, or
    # a username to use 'sudo -u'.

    def sudo=(value)
      with_server_apps :all,
        :msg => "Using sudo = #{value.inspect}" do |server_app|
        server_app.sudo = value
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
    # Upload common rake tasks from the sunshine lib.
    #   app.upload_tasks
    #     #=> upload all tasks
    #   app.upload_tasks 'tpkg', 'common', :role => :web
    #     #=> upload tpkg and common rake files
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
    # Calls a method for deploy_server_apps found with the passed options,
    # and with an optional log message. Supports all DeployServerDispatcher#find
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
      d_servers = @deploy_servers.find search_options

      options = search_options.merge options if Hash === search_options

      message = options[:msg]
      method  = options[:no_threads] ? :each : :threaded_each

      block = lambda do
        d_servers.send(method) do |server_app|

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
      @deploy_path   = path || File.join(Sunshine.web_directory, @name)
      @current_path  = "#{@deploy_path}/current"
      @deploys_dir   = "#{@deploy_path}/deploys"
      @shared_path   = "#{@deploy_path}/shared"
      @log_path      = "#{@shared_path}/log"
      @checkout_path = "#{@deploys_dir}/#{@deploy_name}"
    end


    ##
    # Set the app's deploy servers:
    #   set_deploy_servers DeployServerDispatcher.new("svr1", "svr2", "svr3")
    #
    #   d_servers = [["svr1", {:roles => "web db app"}], "svr2", "svr3"]
    #   set_deploy_servers d_servers

    def set_deploy_servers d_servers

      @deploy_servers = if DeployServerDispatcher === d_servers
        d_servers
      else

        d_servers = d_servers.map do |ds|
          if DeployServer === ds
            ds
          else
            DeployServerApp.new(*[self,*ds])
          end
        end

        DeployServerDispatcher.new(*d_servers)
      end
    end


    ##
    # Set the app's repo:
    #   set_repo SvnRepo.new("myurl")
    #   set_repo :type => :svn, :url => "myurl"

    def set_repo repo_def
      @repo = case repo_def
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
    # Load and merge a yml config file with the app's deploy options hash

    def merge_config_file config_file, options
      return options unless config_file
      env = options[:deploy_env]
      load_config_for(env, config_file).merge options
    end


    ##
    # Loads an app yml config file, gets the default config
    # and the current deploy env and returns a merged config hash.

    def load_config_for deploy_env, config_file
      config_hash = case config_file
                    when File   then YAML.load config_file
                    when String then YAML.load_file config_file
                    end

      return {} unless config_hash

      deploy_env_config = (config_hash[deploy_env] || {}).dup
      deploy_env_config[:inherits] ||= []
      deploy_env_config[:inherits].unshift(:default) if
        :default != deploy_env && config_hash[:default]

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
