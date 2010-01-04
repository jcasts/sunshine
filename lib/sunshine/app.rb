module Sunshine

  class App

    ##
    # Initialize and deploy an application.
    def self.deploy(*args, &block)
      app = new(*args)
      app.deploy!(&block)
      app
    end

    attr_reader :name, :repo, :health, :deploy_servers, :crontab
    attr_accessor :deploy_path, :current_path, :shared_path, :log_path
    attr_accessor :deploy_env

    def initialize(*args)
      config_file = args.shift if String === args.first
      deploy_options = args.empty? ? {} : args.first
      @deploy_env = deploy_options[:deploy_env] || Sunshine.deploy_env
      deploy_options.merge!(load_config(config_file)) if config_file

      @name = deploy_options[:name]

      @deploy_path = deploy_options[:deploy_path]
      @current_path = "#{@deploy_path}/current"
      @deploys_path = "#{@deploy_path}/deploys"
      @shared_path = "#{@deploy_path}/shared"
      @log_path = "#{@shared_path}/log"

      @crontab = Crontab.new(self.name)

      @health = Healthcheck.new(self)

      @repo = Sunshine::Repo.new_of_type \
        deploy_options[:repo][:type], deploy_options[:repo][:url]

      server_list = deploy_options[:deploy_servers].to_a
      server_list = server_list.map do |server_def|
        if Hash === server_def
          host = server_def.keys.first
          server_def = [host, {:roles => server_def[host].split(" ")}]
        end
        DeployServer.new(*server_def.to_a)
      end
      @deploy_servers = DeployServerDispatcher.new(*server_list)

      @shell_env = {
        "RAKE_ENV" => @deploy_env.to_s,
        "RAILS_ENV" => @deploy_env.to_s
      }
      self.shell_env(deploy_options[:shell_env])

      yield(self) if block_given?
    end

    ##
    # Deploy the application to deploy servers and
    # call user's post-deploy code.
    def deploy!(&block)
      Sunshine.logger.info :app, "Beginning deploy of #{@name}" do
        @deploy_servers.connect
      end
      @deploy_servers.each do |deploy_server|
        self.make_app_directory     deploy_server
        self.checkout_codebase      deploy_server
        self.make_deploy_info_file  deploy_server
        self.symlink_current_dir    deploy_server
      end

      yield(self) if block_given?

      self.setup_logrotate
      self.remove_old_deploys

    rescue CriticalDeployError => e
      Sunshine.logger.error :app, "#{e.class}: #{e.message} - cannot deploy" do
        Sunshine.logger.error '>>', e.backtrace.join("\n")
        revert!
        yield(self) if block_given?
      end

    rescue FatalDeployError => e
      Sunshine.logger.fatal :app, "#{e.class}: #{e.message}" do
        Sunshine.logger.error '>>', e.backtrace.join("\n")
      end

    ensure
      Sunshine.logger.info :app, "Ending deploy of #{@name}" do
        deploy_servers.disconnect
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

          if last_deploy
            deploy_server.symlink \
              "#{@deploys_path}/#{last_deploy}", @current_path
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
    # Creates the base application directory.
    def make_app_directory(d_servers = @deploy_servers)
      Sunshine.logger.info :app, "Creating #{@name} base directory" do
        d_servers.run "mkdir -p #{@deploy_path}"
      end

    rescue => e
      raise FatalDeployError, e
    end

    ##
    # Checks out the app's codebase to one or all deploy servers.
    def checkout_codebase(d_servers = @deploy_servers)
      Sunshine.logger.info :app, "Checking out codebase" do
        @repo.checkout_to(d_servers, self.checkout_path)
      end

    rescue => e
      raise CriticalDeployError, e
    end

    ##
    # Creates a VERSION file with deploy information.
    def make_deploy_info_file(d_servers = @deploy_servers)
      Sunshine.logger.info :app, "Creating VERSION file" do
        info = []
        info << "deployed_at: #{Time.now.to_i}"
        info << "deployed_by: #{Sunshine.console.run("whoami")}"
        info << "scm_url: #{@repo.url}"
        info << "scm_rev: #{@repo.revision}"
        contents = info.join("\n")
        d_servers.make_file "#{self.checkout_path}/VERSION", contents
      end

    rescue => e
      Sunshine.logger.warn :app,
        "#{e.class} (non-critical): #{e.message}. Failed creating VERSION file"
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
    # Upload logrotate config file, install dependencies,
    # and add to the crontab.
    def setup_logrotate
      Sunshine.logger.info :app, "Setting up log rotation..." do
        @crontab.add "logrotate",
          "00 * * * * #{@user} /usr/sbin/logrotate --state /dev/null --force "+
          "#{@current_path}/config/logrotate.conf"
        @deploy_servers.each do |deploy_server|
          logrotate_conf =
            build_erb("templates/logrotate/logrotate.conf.erb", binding)
          config_path = "#{@deploy_path}/config"
          deploy_server.run "mkdir -p #{config_path}"
          deploy_server.make_file "#{config_path}/logrotate.conf",
            logrotate_conf
          Sunshine::Dependencies.install 'logrotate', :call =>deploy_server
          Sunshine::Dependencies.install 'mogwai_logpush', :call =>deploy_server
          @crontab.write! deploy_server
        end
      end

    rescue => e
      Sunshine.logger.warn :app,
        "#{e.class} (non-critical): #{e.message}. Failed setting up logrotate."+
        "Log files may not be rotated or pushed to Mogwai!"
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
            rm_deploys = deploys[Sunshine.max_deploy_versions..-1]
            rm_deploys.map!{|d| "#{@deploys_path}/#{d}"}
            deploy_server.run("rm -rf #{rm_deploys.join(" ")}")
          end
        end
      end
    end

    ##
    # Install gem dependencies.
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
    # Run a rake task on any or all deploy servers.
    def rake(command, d_servers = @deploy_servers)
      Sunshine.logger.info :app, "Running Rake task '#{command}'" do
        d_servers.each do |deploy_server|
          Sunshine::Dependencies.install 'rake', :call => deploy_server
          deploy_server.run "cd #{@checkout_path}; rake #{command}"
        end
      end
    end

    ##
    # Determine and return a remote path to checkout code to.
    def checkout_path
      @checkout_path ||= "#{@deploys_path}/#{Time.now.to_i}_#{@repo.revision}"
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
    # Parse an erb file and return the newly created string.
    # Default binding is the app's binding.
    def build_erb(erb_file, custom_binding=nil)
      str = File.read(erb_file)
      ERB.new(str, nil, '-').result(custom_binding || binding)
    end

    private

    def run_geminstaller(deploy_server)
      Sunshine::Dependencies.install 'geminstaller', :call => deploy_server
      deploy_server.run "cd #{self.checkout_path} && geminstaller -e"
    end

    def run_bundler(deploy_server)
      Sunshine::Dependencies.install 'bundler', :call => deploy_server
      deploy_server.run "cd #{self.checkout_path} && gem bundle"
    end

    def load_config(config_file)
      config_hash = YAML.load_file(config_file)
      default_config = config_hash[:defaults] || {}
      current_config = config_hash[@deploy_env] || {}
      default_config.merge(current_config)
    end

  end

end
