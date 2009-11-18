module Sunshine

  class DeployServerDispatcher

    def initialize(app, *deploy_servers)
      @app = app
      @deploy_servers = []
      self.concat(deploy_servers)
    end

    def concat(arr)
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
      @deploy_servers.each &block
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

    %w{connect connected? disconnect upload make_file run os_name symlink}.each do |mname|
      self.class_eval <<-STR
        def #{mname}(*args, &block)
          warn_if_empty
          stat = {}
          self.each do |ds|
            stat[ds.host] = ds.#{mname}(*args, &block)
          end
          stat
        end
      STR
    end


    private

    def warn_if_empty
      Sunshine.logger.warn :deploy_servers, "No deploy servers are configured. The action will not be executed." if self.empty?
    end

  end

end
