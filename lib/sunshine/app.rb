module Sunshine

  class App

    ##
    # Initialize and deploy an application
    def self.deploy(*args, &block)
      app = new(*args)
      app.deploy!(&block)
      app
    end

    attr_reader :name, :repo, :health, :deploy_servers
    attr_accessor :deploy_path, :current_path, :checkout_path, :shared_path

    def initialize(*args, &block)
      config_file = String === args.first ? args.shift : nil
      @deploy_options = Hash === args.first ? args.shift : {}
      config_file ? load_config(config_file) : update_attributes
      yield(self) if block_given?
    end

    ##
    # Loads a yaml config file
    def load_config(config_file)
      config_hash = YAML.load_file(config_file)
      config_hash = (config_hash[:defaults] || {}).merge(config_hash[Sunshine.deploy_env] || {})
      @deploy_options = config_hash.merge(@deploy_options)
      update_attributes
    end

    ##
    # Deploy the application to deploy servers and
    # call user's post-deploy code
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

    rescue CriticalDeployError => e
      Sunshine.logger.error :app, "#{e.class}: #{e.message} - cannot deploy" do
        revert!
        yield(self) if block_given?
      end

    rescue FatalDeployError => e
      Sunshine.logger.fatal :app, "#{e.class}: #{e.message}"

    ensure
      Sunshine.logger.info :app, "Ending deploy of #{@name}" do
        deploy_servers.disconnect
      end
    end

    ##
    # Symlink current directory to previous checkout and remove
    # the current deploy directory
    def revert!
      Sunshine.logger.info :app, "Reverting to previous deploy..." do
        deploy_servers.each do |deploy_server|
          deploy_server.run "rm -rf #{self.checkout_path}"
          last_deploy = deploy_server.run("ls -1 #{@deploys_path}").split("\n").last

          if last_deploy
            deploy_server.symlink("#{@deploys_path}/#{last_deploy}", @current_path)
            Sunshine.logger.info :app, "#{deploy_server.host}: Reverted to #{last_deploy}"
          else
            Sunshine.logger.info :app, "#{deploy_server.host}: No previous deploy to revert to."
          end
        end
      end
    end

    ##
    # Creates the base application directory
    def make_app_directory(d_servers = @deploy_servers)
      Sunshine.logger.info :app, "Creating #{@name} base directory" do
        d_servers.run "mkdir -p #{@deploy_path}"
      end

    rescue => e
      raise FatalDeployError, e.message
    end

    ##
    # Checks out the app's codebase to one or all deploy servers
    def checkout_codebase(d_servers = @deploy_servers)
      Sunshine.logger.info :app, "Checking out codebase" do
        @repo.checkout_to(d_servers, self.checkout_path)
      end

    rescue => e
      raise CriticalDeployError, e.message
    end

    ##
    # Creates a VERSION file with deploy information
    def make_deploy_info_file(d_servers = @deploy_servers)
      Sunshine.logger.info :app, "Creating VERSION file" do
        info = []
        info << "deployed_at: #{Time.now.to_i}"
        info << "deployed_by: #{Sunshine.run_local("whoami")}"
        info << "scm_url: #{@repo.url}"
        info << "scm_rev: #{@repo.revision}"
        contents = info.join("\n")
        d_servers.make_file "#{self.checkout_path}/VERSION", contents
      end

    rescue => e
      Sunshine.logger.warn :app, "#{e.class} (non-critical):#{e.message}. Failed creating VERSION file"
    end

    ##
    # Creates a symlink to the app's checkout path
    def symlink_current_dir(d_servers = @deploy_servers)
      Sunshine.logger.info :app, "Symlinking #{self.checkout_path} -> #{@current_path}" do
        d_servers.symlink(self.checkout_path, @current_path)
      end

    rescue => e
      raise CriticalDeployError, e.message
    end

    ##
    # Install gem dependencies
    def install_gems(d_servers = @deploy_servers)
      Sunshine.logger.info :app, "Installing gems" do
        d_servers.each do |deploy_server|
          run_geminstaller(deploy_server) if deploy_server.file?("#{@checkout_path}/config/geminstaller.yml")
          run_bundler(deploy_server) if deploy_server.file?("#{@checkout_path}/Gemfile")
        end
      end

    rescue => e
      raise CriticalDeployError, e.message
    end

    ##
    # Determine and return a remote path to checkout code to
    def checkout_path
      @checkout_path ||= "#{@deploys_path}/#{Time.now.to_i}_#{@repo.revision}"
    end


    private

    def run_geminstaller(deploy_server)
      Sunshine::Dependencies.install 'geminstaller',
        :console => deploy_server
      deploy_server.run "cd #{self.checkout_path} && geminstaller"
    end

    def run_bundler(deploy_server)
      Sunshine::Dependencies.install 'bundler',
        :console => deploy_server
      deploy_server.run "cd #{self.checkout_path} && gem bundle"
    end

    def update_attributes(config_hash = @deploy_options)
      @name = config_hash[:name]

      @repo = Sunshine::Repo.new_of_type(config_hash[:repo][:type], config_hash[:repo][:url])

      @deploy_path = config_hash[:deploy_path]
      @current_path = "#{@deploy_path}/current"
      @deploys_path = "#{@deploy_path}/deploys"
      @shared_path = "#{@deploy_path}/shared"

      @health = Healthcheck.new(self)

      server_list = config_hash[:deploy_servers].to_a
      server_list = server_list.map do |server_def|
        if Hash === server_def
          host = server_def.keys.first
          server_def = [host, {:roles => server_def[host].split(" ")}]
        end
        DeployServer.new(*server_def.to_a)
      end
      @deploy_servers = DeployServerDispatcher.new(*server_list)
    end

  end

end
