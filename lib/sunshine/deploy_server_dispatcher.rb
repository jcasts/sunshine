module Sunshine

  class DeployServerDispatcher < Array

    def initialize(*deploy_servers)
      self.concat(deploy_servers)
    end

    %w{connect connected? disconnect upload make_file! run os_name}.each do |mname|
      self.class_eval <<-STR
        def #{mname}(*args, &block)
          stat = {}
          self.each do |ds|
            stat[ds.host] = ds.#{mname}(*args, &block)
          end
          stat
        end
      STR
    end

  end

end
