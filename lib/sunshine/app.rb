module Sunshine

  class App

    def self.deploy(*args, &block)
      app = new *args
      app.deploy!
      yield(app) if block_given?
      app
    end

    attr_reader :name, :repo, :deploy_path, :deploy_servers, :deploy_options

    def initialize(*args, &block)
      config_file = String === args.first ? args.shift : nil
      @deploy_options = Hash === args.first ? args.shift : {}
      update_attributes

      load_config(config_file) if config_file

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
        run_healthcheck server
        check_version server
      end
    end

    def checkout_codebase(server)
      server.run command(:checkout_codebase)
    end

    def run_healthcheck(server)
      server.run command(:healthcheck)
    end

    def check_version(server)
      server.run command(:check_version)
    end

    private

    def update_attributes(config_hash=@deploy_options)
      @repo = config_hash[:repo]
      @name = config_hash[:name]
      @deploy_path = config_hash[:deploy_path]
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
