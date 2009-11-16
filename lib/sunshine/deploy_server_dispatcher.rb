module Sunshine

  class DeployServerDispatcher < Array

    def initialize(app, *deploy_servers)
      @app = app
      self.concat(deploy_servers)
    end

    def concat(arr)
      arr.each do |ds|
        self << ds
      end
    end

    def <<(deploy_server)
      deploy_server = DeployServer.new(deploy_server, @app) unless DeployServer === deploy_server
      self.push(deploy_server) if self.select{|ds| ds.host == deploy_server.host}.empty?
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

    %w{each each_with_index}.each do |mname|
      self.class_eval <<-STR
        def #{mname}(*args, &block)
          warn_if_empty
          super
        end
      STR
    end

    private

    def warn_if_empty
      Sunshine.info :deploy_servers, "No deploy servers are configured. The action will not be executed.", :indent => 1, :nl => 0 if self.empty?
    end

  end

end
