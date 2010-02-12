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
    attr_reader :deploys_dir, :shared_path, :log_path
    attr_accessor :deploy_env, :scripts, :info, :source_path


    def initialize(*args)
      config_file    = args.shift unless Hash === args.first
      config_file  ||= Sunshine::DATA if defined?(Sunshine::DATA)

      deploy_options = args.empty? ? {} : args.first.dup
      deploy_options[:deploy_env] ||= Sunshine.deploy_env

      deploy_options = merge_config_file config_file, deploy_options


      set_deploy_paths deploy_options[:deploy_path]

      @name       = deploy_options[:name]
      @crontab    = Crontab.new @name
      @deploy_env = deploy_options[:deploy_env]

      set_repo deploy_options[:repo]

      @source_path = deploy_options[:source_path] || Dir.pwd

      set_deploy_servers deploy_options[:deploy_servers]

      self.sudo = deploy_options[:sudo] || Sunshine.sudo

      @health = Healthcheck.new @shared_path, @deploy_servers

      deploy_options[:shell_env] ||= {
        "PATH"      => "/home/t/bin:/home/ypc/sbin:$PATH",
        "RACK_ENV"  => @deploy_env.to_s,
        "RAILS_ENV" => @deploy_env.to_s
      }
      shell_env deploy_options[:shell_env]

      @scripts = Hash.new{|h, k| h[k] = []}

      @post_user_lambdas = []

      @deploy_successful = false

      @info = {
        :ports => Hash.new{|h,k| h[k] = {}}
      }
    end


    ##
    # Deploy the application to deploy servers and
    # call user's post-deploy code.

    def deploy!(&block)
      Sunshine.logger.info :app, "Beginning deploy of #{@name}" do
        @deploy_servers.connect
      end

      make_app_directories
      checkout_codebase
      symlink_current_dir

      yield(self) if block_given?

      run_post_user_lambdas
      build_control_scripts
      make_deploy_info_file
      remove_old_deploys
      register_as_deployed

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
      Sunshine.logger.info :app, "Reverting to previous deploy..." do
        deploy_servers.each do |deploy_server|
          deploy_server.call "rm -rf #{@checkout_path}"

          last_deploy =
            deploy_server.call("ls -1 #{@deploys_dir}").split("\n").last

          if last_deploy && !last_deploy.empty?
            deploy_server.symlink \
              "#{@deploys_dir}/#{last_deploy}", @current_path

            started = StartCommand.exec [@name],
              'servers' => @deploy_servers, 'force' => true

            Sunshine.logger.info :app,
              "#{deploy_server.host}: Reverted to #{last_deploy}"

            Sunshine.logger.error :app, "Failed starting #{@name}" if !started

          else
            Sunshine.logger.info :app,
              "#{deploy_server.host}: No previous deploy to revert to."
          end
        end
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
    # Creates and uploads a control script for the application with
    # start/stop/restart commands. To add to, or define a control script,
    # use the app's script attribute:
    #   app.script[:start] << "do this for app startup"
    #   app.script[:custom] << "this is my own script"

    def build_control_scripts(d_servers = @deploy_servers)
      Sunshine.logger.info :app, "Building control scripts" do

        chmod = '--chmod=ugo=rwx'

        bash = make_env_bash_script
        d_servers.make_file "#{@checkout_path}/env", bash, :flags => chmod
        d_servers.symlink "#{@current_path}/env", "#{@deploy_path}/env"

        if @scripts[:restart].empty? &&
          !@scripts[:start].empty? && !@scripts[:stop].empty?
          @scripts[:restart] << "#{@deploy_path}/stop"
          @scripts[:restart] << "#{@deploy_path}/start"
        end

        @scripts.each do |name, cmds|
          Sunshine.logger.warn :app, "#{name} script is empty" if cmds.empty?
          bash = make_bash_script name, cmds

          d_servers.make_file "#{@checkout_path}/#{name}", bash, :flags => chmod
          d_servers.symlink "#{@current_path}/#{name}",
            "#{@deploy_path}/#{name}"
        end
      end
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

    def checkout_codebase(d_servers = @deploy_servers)
      repo_info = {}

      Sunshine.logger.info :app, "Checking out codebase" do
        d_servers.each do |deploy_server|
          repo_info = @repo.checkout_to(deploy_server, @checkout_path)
        end
      end

      @info[:scm_url]    = repo_info[:url]
      @info[:scm_rev]    = repo_info[:revision]
      @info[:scm_branch] = repo_info[:branch]
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
    # Install dependencies defined as a Sunshine dependency object:
    #   rake   = Sunshine::Dependencies.gem 'rake', :version => '~>0.8'
    #   apache = Sunshine::Dependencies.yum 'apache'
    #   app.install_deps rake, apache
    #
    # Deploy servers can also be specified as a dispatcher, array, or single
    # deploy server, by passing the :servers option:
    #   postgres = Sunshine::Dependencies.yum 'postgresql'
    #   pgserver = Sunshine::Dependencies.yum 'postgresql-server'
    #   app.install_deps postgres, pgserver,
    #     :servers => app.deploy_servers.find(:role => 'db')
    #
    # If a dependency was already defined in the Sunshine dependency tree,
    # the dependency name may be passed instead of the object:
    #   app.install_deps 'nginx', 'ruby'

    def install_deps(*deps)
      options   = Hash === deps[-1] ? deps.delete_at(-1) : {}
      d_servers = [*(options[:servers] || @deploy_servers)]

      Sunshine.logger.info :app,
        "Installing dependencies: #{deps.map{|d| d.to_s}.join(" ")}" do

        d_servers.each do |deploy_server|
          deps.each do |d|
            d = Sunshine::Dependencies[d] if String === d
            d.install! :call => deploy_server
          end
        end
      end
    end


    ##
    # Install gem dependencies defined by the app's checked-in
    # bundler or geminstaller config.

    def install_gems(d_servers = @deploy_servers)
      Sunshine.logger.info :app, "Installing gems" do
        d_servers.each do |deploy_server|

          run_geminstaller(deploy_server) if
            deploy_server.file?("#{@checkout_path}/config/geminstaller.yml")

          run_bundler(deploy_server) if
            deploy_server.file?("#{@checkout_path}/Gemfile")
        end
      end

    rescue => e
      raise CriticalDeployError, e
    end


    ##
    # Creates the required application directories.

    def make_app_directories(d_servers = @deploy_servers)
      Sunshine.logger.info :app, "Creating #{@name} directories" do
        d_servers.call "mkdir -p #{directories.join(" ")}"
      end

    rescue => e
      raise FatalDeployError, e
    end


    ##
    # Creates a yaml file with deploy information. To add custom information
    # to the info file, use the app's info hash attribute:
    #   app.info[:key] = "some value"

    def make_deploy_info_file(d_servers = @deploy_servers)
      Sunshine.logger.info :app, "Creating info file" do

        contents = {
          :deployed_at => Time.now,
          :deployed_by => Sunshine.console.user,
          :deploy_name => File.basename(@checkout_path),
          :path        => @deploy_path
        }.merge @info

        d_servers.each do |deploy_server|
          contents[:deployed_as] ||= deploy_server.call "whoami"

          deploy_server.make_file "#{@checkout_path}/info", contents.to_yaml
          deploy_server.symlink "#{@current_path}/info", "#{@deploy_path}/info"
        end
      end

    rescue => e
      Sunshine.logger.warn :app,
        "#{e.class} (non-critical): #{e.message}. Failed creating info file"
    end


    ##
    # Run a rake task on any or all deploy servers.

    def rake(command, d_servers = @deploy_servers)
      Sunshine.logger.info :app, "Running Rake task '#{command}'" do
        d_servers.each do |deploy_server|
          self.install_deps 'rake', :servers => deploy_server
          deploy_server.call "cd #{@checkout_path} && rake #{command}"
        end
      end
    end


    ##
    # Adds the app to the deploy servers deployed-apps list

    def register_as_deployed(d_servers = @deploy_servers)
      Sunshine.logger.info :app, "Registering app with deploy servers" do
        AddCommand.exec @deploy_path, 'servers' => d_servers
      end
    end


    ##
    # Removes old deploys from the checkout_dir
    # based on Sunshine's max_deploy_versions.

    def remove_old_deploys(d_servers = @deploy_servers)
      Sunshine.logger.info :app,
        "Removing old deploys (max = #{Sunshine.max_deploy_versions})" do

        d_servers.each do |deploy_server|
          deploys = deploy_server.call("ls -1 #{@deploys_dir}").split("\n")

          if deploys.length > Sunshine.max_deploy_versions
            lim = Sunshine.max_deploy_versions + 1
            rm_deploys = deploys[0..-lim]
            rm_deploys.map!{|d| "#{@deploys_dir}/#{d}"}

            deploy_server.call("rm -rf #{rm_deploys.join(" ")}")
          end
        end
      end
    end


    ##
    # Run lambdas that were saved for after the user's script.
    # See #after_user_script.

    def run_post_user_lambdas
      @post_user_lambdas.each{|l| l.call self}
    end


    ##
    # Upload logrotate config file, install dependencies,
    # and add to the crontab.

    def setup_logrotate(d_servers = @deploy_servers)
      Sunshine.logger.info :app, "Setting up log rotation..." do

        @crontab.add "logrotate",
          "00 * * * * /usr/sbin/logrotate"+
          " --state /dev/null --force #{@current_path}/config/logrotate.conf"

        d_servers.each do |deploy_server|
          self.install_deps 'logrotate', 'mogwai_logpush',
            :servers => deploy_server

          logrotate_conf =
            build_erb("templates/logrotate/logrotate.conf.erb", binding)

          config_path    = "#{@checkout_path}/config"
          logrotate_path = "#{config_path}/logrotate.conf"

          deploy_server.call "mkdir -p #{config_path} #{@log_path}/rotate"
          deploy_server.make_file logrotate_path, logrotate_conf

          @crontab.write! deploy_server
        end
      end

    rescue => e
      Sunshine.logger.warn :app,
        "#{e.class} (non-critical): #{e.message}. Failed setting up logrotate."+
        "Log files may not be rotated or pushed to Mogwai!"
    end


    ##
    # Set and return the remote shell env variables.
    # Also assigns shell environment to the app's deploy servers.

    def shell_env env_hash=nil
      env_hash ||= {}
      @shell_env ||= {}

      @shell_env.merge!(env_hash)

      @deploy_servers.each do |deploy_server|
        deploy_server.env.merge!(@shell_env)
      end

      Sunshine.logger.info :app, "Shell env: #{@shell_env.inspect}"
      @shell_env.dup
    end


    ##
    # Use sudo on deploy servers. Set to true/false, or
    # a username to use 'sudo -u'.

    def sudo=(value)
      @deploy_servers.each do |deploy_server|
        deploy_server.sudo = value
      end
      @sudo = value
      Sunshine.logger.info :app, "Using sudo = #{value.inspect}"
    end


    ##
    # Creates a symlink to the app's checkout path.

    def symlink_current_dir(d_servers = @deploy_servers)
      Sunshine.logger.info :app,
        "Symlinking #{@checkout_path} -> #{@current_path}" do
        d_servers.symlink(@checkout_path, @current_path)
      end

    rescue => e
      raise CriticalDeployError, e
    end


    ##
    # Uploads the app's source to deploy servers.

    def upload_source(d_servers = @deploy_servers)
      Sunshine.logger.info :app,
        "Uploading #{@name} source: #{@source_path}" do
        d_servers.upload @source_path, @current_path
      end

    rescue => e
      raise FatalDeployError, e
    end


    ##
    # Upload common rake tasks from the sunshine lib.
    #   app.upload_tasks
    #     #=> upload all tasks
    #   app.upload_tasks 'tpkg', 'common', ...
    #     #=> upload tpkg and common rake files
    #
    # Allows options:
    # :servers:: ary - a deploy_server, a deploy server dispatcher/array
    # :path:: str - the remote absolute path to upload the files to

    def upload_tasks *files
      options   = Hash === files[-1] ? files.delete_at(-1) : {}
      d_servers = [*(options[:servers] || @deploy_servers)]
      path      = options[:path] || "#{@checkout_path}/lib/tasks"

      files.map!{|f| "templates/tasks/#{f}.rake"}
      files = Dir.glob("templates/tasks/*") if files.empty?

      Sunshine.logger.info :app, "Uploading tasks: #{files.join(" ")}" do
        files.each do |f|
          remote = File.join(path, File.basename(f))
          d_servers.each do |deploy_server|
            deploy_server.call "mkdir -p #{path}"
            deploy_server.upload f, remote
          end
        end
      end
    end


    private

    ##
    # Set all the app paths based on the root deploy path.

    def set_deploy_paths path
      @deploy_path   = path
      @current_path  = "#{@deploy_path}/current"
      @deploys_dir   = "#{@deploy_path}/deploys"
      @shared_path   = "#{@deploy_path}/shared"
      @log_path      = "#{@shared_path}/log"
      @checkout_path = "#{@deploys_dir}/#{Time.now.to_i}"
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
        DeployServerDispatcher.new(*d_servers)
      end
    end


    ##
    # Set the app's repo:
    #   set_repo SvnRepo.new("myurl")
    #   set_repo :type => :svn, :url => "myurl"

    def set_repo repo_def
      @repo = if Sunshine::Repo === repo_def
        repo_def
      elsif repo_def
        Sunshine::Repo.new_of_type repo_def[:type], repo_def[:url], repo_def
      end
    end


    ##
    # Load and merge a yml config file with the app's deploy_options hash

    def merge_config_file config_file, deploy_options
      return deploy_options unless config_file
      env = deploy_options[:deploy_env]
      load_config_for(env, config_file).merge deploy_options
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


    ##
    # Makes an array of bash commands into a script that
    # echoes 'true' on success.

    def make_bash_script name, cmds
      cmds = cmds.map{|cmd| "(#{cmd})" }
      cmds << "echo true"
      bash = <<-STR
#!/bin/bash
if [ "$1" == "--no-env" ]; then
  #{cmds.flatten.join(" && ")}
else
  #{@deploy_path}/env #{@deploy_path}/#{name} --no-env
fi
      STR
    end


    ##
    # Creates the one-off env script that will be used by other scripts
    # to correctly set their env variables.

    def make_env_bash_script
      env_str = @shell_env.map{|e| e.join("=")}.join(" ")
      "#!/bin/bash\nenv #{env_str} \"$@\""
    end


    ##
    # Run geminstaller on a given deploy server.

    def run_geminstaller deploy_server
      self.install_deps 'geminstaller', :servers => deploy_server
      deploy_server.call "cd #{@checkout_path} && geminstaller -e"
    end


    ##
    # Run bundler on a given deploy server.

    def run_bundler deploy_server
       self.install_deps 'bundler', :servers => deploy_server
      deploy_server.call "cd #{@checkout_path} && gem bundle"
    end
  end
end
