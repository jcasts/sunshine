module Sunshine

  class App

    def self.deploy(*args, &block)
      app = new *args
      Sunshine.info :app, "Beginning deploy of #{app.name}"
      app.deploy_servers.connect
      app.deploy!
      yield(app) if block_given?
      Sunshine.info :app, "Finishing deploy of #{app.name}"
      app.deploy_servers.disconnect
      app
    end

    attr_reader :name, :repo, :public_domain_name, :deploy_servers, :deploy_options
    attr_reader :deploy_path, :current_path, :checkout_path, :shared_path
    attr_reader :health

    def initialize(*args, &block)
      config_file = String === args.first ? args.shift : nil
      @deploy_options = Hash === args.first ? args.shift : {}
      @deploy_block = block

      load_config(config_file) if config_file
      update_attributes

      yield(self) if block_given?
    end

    def load_config(config_file)
      config_hash = YAML.load_file(config_file)
      config_hash = (config_hash[:defaults] || {}).merge(config_hash[Sunshine.deploy_env] || {})
      @deploy_options = config_hash.merge(@deploy_options)
      update_attributes
    end

    def deploy!
      deploy_servers.each do |server|
        checkout_codebase server
        make_deploy_info_file server
        update_current_dir server
        # if we implement yield in 'deploy!', put it here
        # app servers must start here
        # run_healthcheck server
      end
    end

    def checkout_codebase(deploy_server=nil)
      Sunshine.info :app, "Checking out codebase"
      deploy_server ||= @deploy_servers
      @repo.checkout_to(deploy_server, @checkout_path)
    end

    def make_deploy_info_file(deploy_server=nil)
      Sunshine.info :app, "Creating VERSION file"
      deploy_server ||= @deploy_servers
      info = []
      info << "deployed_at: #{Time.now.to_i}"
      info << "deployed_by: #{Sunshine.run_local("whoami")}"
      info << "scm_url: #{@repo.url}"
      info << "scm_rev: #{@repo.revision}"
      contents = info.join("\n")
      deploy_server.make_file! "#{@checkout_path}/VERSION", contents
    end

    def update_current_dir(deploy_server=nil)
      deploy_server ||= @deploy_servers
      set_current_app_dir(@checkout_path, deploy_server)
    end

    def set_current_app_dir(new_dir, deploy_server=nil)
      Sunshine.info :app, "Symlinking #{new_dir} -> #{@current_path}"
      deploy_server ||= @deploy_servers
      deploy_server.run "ln -sfT #{new_dir} #{@current_path}"
    end

    def install_dependency(dep_name, deploy_server=nil)
      deploy_server ||= @deploy_servers
      # TODO: probably will implement yum, apt, or tpkg
    end

    def install_gems(deploy_server=nil)
      deploy_server ||= @deploy_servers
      deploy_server.run "gem install geminstaller; cd #{@checkout_path} && geminstaller"
    end

    private

    def deploy_server_list(server=nil, &block)
      server_list = server.nil? ? deploy_servers : [server]
      if block_given?
        server_list.each do |deploy_server|
          yield deploy_server
        end
      end
      server_list
    end

    def update_attributes(config_hash=@deploy_options)
      @repo = Sunshine::Repo.new_of_type(config_hash[:repo][:type], config_hash[:repo][:url])
      @name = config_hash[:name]
      @public_domain_name = config_hash[:public_domain_name] || "#{@name}.atti.com"
      @deploy_path = config_hash[:deploy_path]
      @current_path = "#{@deploy_path}/current"
      @checkout_path = "#{@deploy_path}/revisions/#{@repo.revision}"
      @shared_path = "#{@deploy_path}/shared"
      @health = Healthcheck.new(self)

      server_list = config_hash[:deploy_servers] || ["#{Sunshine.deploy_env}-#{@name}.atti.com"]
      @deploy_servers = DeployServerDispatcher.new(self, *server_list)
    end

  end

end
