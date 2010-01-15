module Sunshine

  class App

    ##
    # Initialize and deploy an application.

    def self.deploy(*args, &block)
      app = new(*args)
      app.deploy!(&block)
      app
    end


    attr_reader :name, :repo, :deploy_servers, :crontab, :health
    attr_reader :deploy_path, :checkout_path, :current_path
    attr_reader :shared_path, :log_path
    attr_accessor :deploy_env, :scripts, :info


    def initialize(*args)
      config_file    = args.shift if String === args.first
      deploy_options = args.empty? ? {} : args.first
      @deploy_env    = deploy_options[:deploy_env] || Sunshine.deploy_env

      deploy_options.merge!(load_config(config_file)) if config_file


      @name = deploy_options[:name]

      repo_url  = deploy_options[:repo][:url]
      repo_type = deploy_options[:repo][:type]
      @repo     = Sunshine::Repo.new_of_type repo_type, repo_url

      @deploy_path   = deploy_options[:deploy_path]
      @current_path  = "#{@deploy_path}/current"
      @deploys_path  = "#{@deploy_path}/deploys"
      @shared_path   = "#{@deploy_path}/shared"
      @log_path      = "#{@shared_path}/log"
      @checkout_path = "#{@deploys_path}/#{Time.now.to_i}_#{@repo.revision}"

      @post_user_lambdas = []


      @crontab  = Crontab.new self.name


      server_list = [*deploy_options[:deploy_servers]]
      server_list = server_list.map do |server_def|
        if Hash === server_def
          host = server_def.keys.first
          server_def = [host, {:roles => server_def[host].split(" ")}]
        end
        DeployServer.new(*server_def)
      end

      @deploy_servers = DeployServerDispatcher.new(*server_list)


      @health = Healthcheck.new @shared_path, @deploy_servers

      @shell_env = {
        "RAKE_ENV"  => @deploy_env.to_s,
        "RAILS_ENV" => @deploy_env.to_s
      }
      self.shell_env deploy_options[:shell_env]


      @scripts = Hash.new{|h, k| h[k] = []}

      @info = {
        :deployed_at => Time.now,
        :deployed_by => Sunshine.console.user,
        :scm_url     => @repo.url,
        :scm_rev     => @repo.revision
      }

      yield(self) if block_given?
    end


    ##
    # Deploy the application to deploy servers and
    # call user's post-deploy code.

    def deploy!(&block)
      Sunshine.logger.info :app, "Beginning deploy of #{@name}" do
        @deploy_servers.connect
      end

      make_app_directory
      checkout_codebase
      symlink_current_dir

      yield(self) if block_given?

      run_post_user_lambdas
      setup_logrotate
      build_control_scripts
      make_deploy_info_file
      remove_old_deploys
      register_as_deployed

    rescue CriticalDeployError => e
      Sunshine.logger.error :app, "#{e.class}: #{e.message} - cannot deploy" do
        Sunshine.logger.error '>>', e.backtrace.join("\n")
        revert!
      end

    rescue FatalDeployError => e
      Sunshine.logger.fatal :app, "#{e.class}: #{e.message}" do
        Sunshine.logger.error '>>', e.backtrace.join("\n")
      end

    ensure
      Sunshine.logger.info :app, "Ending deploy of #{@name}" do
        @deploy_servers.disconnect
      end
    end


    ##
    # Symlink current directory to previous checkout and remove
    # the current deploy directory.

    def revert!
      Sunshine.logger.info :app, "Reverting to previous deploy..." do
        deploy_servers.each do |deploy_server|
          deploy_server.run "rm -rf #{self.checkout_path}"

          last_deploy =
            deploy_server.run("ls -1 #{@deploys_path}").split("\n").last

          if last_deploy && !last_deploy.empty?
            deploy_server.symlink \
              "#{@deploys_path}/#{last_deploy}", @current_path

            StartCommand.exec [@name],
              'servers' => @deploy_servers, 'force' => true

            Sunshine.logger.info :app,
              "#{deploy_server.host}: Reverted to #{last_deploy}"
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
    # start/stop commands.

    def build_control_scripts(d_servers = @deploy_servers)
      Sunshine.logger.info :app, "Building control scripts" do

        if @scripts[:restart].empty? &&
          !@scripts[:start].empty? && !@scripts[:stop].empty?
          @scripts[:restart] << "#{@deploy_path}/stop"
          @scripts[:restart] << "#{@deploy_path}/start"
        end

        @scripts.each do |name, cmds|
          Sunshine.logger.warn :app, "#{name} script is empty" if cmds.empty?
          bash = make_bash_script cmds

          d_servers.each do |deploy_server|
            deploy_server.make_file "#{@deploy_path}/#{name}", bash
            deploy_server.run "chmod 0755 #{@deploy_path}/#{name}"
          end
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
      Sunshine.logger.info :app, "Checking out codebase" do
        d_servers.each do |deploy_server|
          @repo.checkout_to(deploy_server, self.checkout_path)
        end
      end

    rescue => e
      raise CriticalDeployError, e
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
        "Installing dependencies: #{deps.map{|d| d.to_s}.join(" ")}"

      d_servers.each do |deploy_server|
        deps.each do |d|
          d = Sunshine::Dependencies[d] if String === d
          d.install! :call => deploy_server
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
            deploy_server.file?("#{self.checkout_path}/config/geminstaller.yml")

          run_bundler(deploy_server) if
            deploy_server.file?("#{self.checkout_path}/Gemfile")
        end
      end

    rescue => e
      raise CriticalDeployError, e
    end


    ##
    # Creates the base application directory.

    def make_app_directory(d_servers = @deploy_servers)
      Sunshine.logger.info :app, "Creating #{@name} base directory" do
        d_servers.run "mkdir -p #{@deploy_path}"
      end

    rescue => e
      raise FatalDeployError, e
    end


    ##
    # Creates an info file with deploy information.

    def make_deploy_info_file(d_servers = @deploy_servers)
      Sunshine.logger.info :app, "Creating info file" do
        contents = @info.to_yaml

        d_servers.each do |deploy_server|
          deploy_server.make_file "#{@deploy_path}/info", contents
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
          deploy_server.run "cd #{self.checkout_path}; rake #{command}"
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
          deploys = deploy_server.run("ls -1 #{@deploys_path}").split("\n")

          if deploys.length > Sunshine.max_deploy_versions
            rm_deploys = deploys[0..-Sunshine.max_deploy_versions]
            rm_deploys.map!{|d| "#{@deploys_path}/#{d}"}

            deploy_server.run("rm -rf #{rm_deploys.join(" ")}")
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

          config_path    = "#{self.checkout_path}/config"
          logrotate_path = "#{config_path}/logrotate.conf"

          deploy_server.run "mkdir -p #{config_path} #{@log_path}/rotate"
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

    def shell_env(env_hash=nil)
      env_hash ||= {}

      @shell_env.merge!(env_hash)

      @deploy_servers.each do |deploy_server|
        deploy_server.env.merge!(@shell_env)
      end

      Sunshine.logger.info :app, "Shell env: #{@shell_env.inspect}"
      @shell_env.dup
    end


    ##
    # Creates a symlink to the app's checkout path.

    def symlink_current_dir(d_servers = @deploy_servers)
      Sunshine.logger.info :app,
        "Symlinking #{self.checkout_path} -> #{@current_path}" do
        d_servers.symlink(self.checkout_path, @current_path)
      end

    rescue => e
      raise CriticalDeployError, e
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
      path      = options[:path] || "#{self.checkout_path}/lib/tasks"

      files.map!{|f| "templates/tasks/#{f}.rake"}
      files = Dir.glob("templates/tasks/*") if files.empty?

      Sunshine.logger.info :app, "Uploading tasks: #{files.join(" ")}" do
        files.each do |f|
          remote = File.join(path, File.basename(f))
          d_servers.each do |deploy_server|
            deploy_server.run "mkdir -p #{path}"
            deploy_server.upload f, remote
          end
        end
      end
    end


    private

    def load_config(config_file)
      config_hash = YAML.load_file(config_file)
      default_config = config_hash[:defaults] || {}
      current_config = config_hash[@deploy_env] || {}
      default_config.merge(current_config)
    end


    def make_bash_script cmds
      cmds = cmds.map{|cmd| "(#{cmd})" }
      cmds << "echo true"
      "#!/bin/bash\n#{cmds.flatten.join(" && ")};"
    end


    def run_geminstaller(deploy_server)
      self.install_deps 'geminstaller', :servers => deploy_server
      deploy_server.run "cd #{self.checkout_path} && geminstaller -e"
    end


    def run_bundler(deploy_server)
       self.install_deps 'bundler', :servers => deploy_server
      deploy_server.run "cd #{self.checkout_path} && gem bundle"
    end
  end
end
