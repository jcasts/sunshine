module Sunshine

  class App

    def self.deploy(*args, &block)
      app = new *args
      app.deploy!
      yield(app) if block_given?
      app
    end

    attr_reader :name, :repo, :deploy_path, :current_path, :checkout_path, :deploy_servers, :deploy_options

    def initialize(*args, &block)
      config_file = String === args.first ? args.shift : nil
      @deploy_options = Hash === args.first ? args.shift : {}

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
        # app servers must start here
        # run_healthcheck server
      end
    end

    def checkout_codebase(server)
      @repo.checkout_to(server, @checkout_path)
    end

    def run_healthcheck(server)
      server.run command(:healthcheck)
    end

    def make_deploy_info_file(server)
      info = []
      info << "deployed_at: #{Time.now.to_i}"
      info << "deployed_by: #{server.user}"
      info << "scm_url: #{@repo.url}"
      info << "scm_rev: #{@repo.revision}"
      server.make_file! "#{@current_path}/VERSION", info.join("\n")
    end

    private

    def update_attributes(config_hash=@deploy_options)
      @repo = Sunshine::Repo.new_of_type(config_hash[:repo][:type], config_hash[:repo][:url])
      @name = config_hash[:name]
      @deploy_path = config_hash[:deploy_path]
      @current_path = "#{@deploy_path}/current"
      @checkout_path = "#{@deploy_path}/revisions/#{@repo.revision}"
      server_list = config_hash[:deploy_servers] || ["#{Sunshine.deploy_env}-#{@name}.atti.com"]
      @deploy_servers = server_list.map do |ds|
        Sunshine::DeployServer.new(ds, self)
      end
    end

    def command(cmd_name)
      Sunshine::Commands.method(cmd_name).call(self)
    end

  end

end
