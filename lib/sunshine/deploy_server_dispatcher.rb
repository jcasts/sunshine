module Sunshine

  class DeployServerDispatcher

    def initialize(app, *deploy_servers)
      @app = app
      @deploy_servers = []
      self.add(*deploy_servers)
    end

    def add(*arr)
      arr.each do |ds|
        self << ds
      end
    end

    def <<(deploy_server)
      deploy_server = DeployServer.new(deploy_server, @app) unless DeployServer === deploy_server
      @deploy_servers.push(deploy_server) unless self.exist?(deploy_server)
    end

    def each(&block)
      warn_if_empty
      threads = []
      @deploy_servers.each do |deploy_server|
        threads << Thread.new{ block.call(deploy_server) }
      end
      threads.each{|thr| thr.join}
    end

    def exist?(deploy_server)
      deploy_server_host = deploy_server.host rescue deploy_server.split("@").last
      !@deploy_servers.select{|ds| ds.host == deploy_server_host}.empty?
    end

    def empty?
      @deploy_servers.empty?
    end

    def length
      @deploy_servers.length
    end

    ##
    # Forward to deploy servers

    def connect(*args, &block)
      call_each_method :connect, *args, &block
    end

    def connected?(*args, &block)
      call_each_method :connected?, *args, &block
    end

    def disconnect(*args, &block)
      call_each_method :disconnect, *args, &block
    end

    def symlink(*args, &block)
      call_each_method :symlink, *args, &block
    end

    def upload(*args, &block)
      call_each_method :upload, *args, &block
    end

    def make_file(*args, &block)
      call_each_method :make_file, *args, &block
    end

    def os_name(*args, &block)
      call_each_method :os_name, *args, &block
    end

    def run(*args, &block)
      call_each_method :run, *args, &block
    end


    private

    def call_each_method(method_name, *args, &block)
      results = {}
      self.each do |deploy_server|
        results[deploy_server.host] = deploy_server.method(method_name).call(*args, &block)
      end
      results
    end

    def warn_if_empty
      return unless self.empty?
      Sunshine.logger.warn :deploy_servers,
        "No deploy servers are configured. The action will not be executed."
    end

  end

end
