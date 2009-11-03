module Sunshine

  class App

    def self.deploy(*args, &block)
      app = new *args
      app.deploy!
      yield(app) if block_given?
      app
    end

    attr_reader :name, :repo, :public_domain_name, :deploy_servers, :deploy_options
    attr_reader :deploy_path, :current_path, :checkout_path, :shared_path

    def initialize(*args, &block)
      config_file = String === args.first ? args.shift : nil
      @deploy_options = Hash === args.first ? args.shift : {}
      @deploy_block = block

      load_config(config_file) if config_file
      update_attributes

      yield(self) if block_given?
    end

    def [](key)
      @deploy_options[key]
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
      deploy_server_list(deploy_server) do |ds|
        @repo.checkout_to(ds, @checkout_path)
      end
    end

    def run_healthcheck(server=nil)
      # TODO
    end

    def make_deploy_info_file(deploy_server=nil)
      info = []
      info << "deployed_at: #{Time.now.to_i}"
      info << "deployed_by: #{Sunshine.run_local("whoami")}"
      info << "scm_url: #{@repo.url}"
      info << "scm_rev: #{@repo.revision}"
      contents = info.join("\n")
      deploy_server_list(deploy_server) do |ds|
        ds.make_file! "#{@checkout_path}/VERSION", contents
      end
    end

    def update_current_dir(deploy_server=nil)
      set_current_app_dir(@checkout_path, deploy_server)
    end

    def set_current_app_dir(new_dir, deploy_server=nil)
      deploy_server_list(deploy_server) do |ds|
        ds.run "ln -f #{new_dir} #{@current_path}"
      end
    end

    def install_libs(deploy_server=nil)
      # TODO: probably will implement tpkg
    end

    def install_gems(deploy_server=nil)
      deploy_server_list(deploy_server) do |ds|
        ds.run "gem install geminstaller"
        ds.run "geminstaller"
      end
    end

    private

    def deploy_server_list(server=nil, &block)
      server_list = server.nil? deploy_servers : [server]
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
      server_list = config_hash[:deploy_servers] || ["#{Sunshine.deploy_env}-#{@name}.atti.com"]
      @deploy_servers = server_list.map do |ds|
        Sunshine::DeployServer.new(ds, self)
      end
    end

  end

end
