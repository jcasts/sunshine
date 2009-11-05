module Sunshine

  class Unicorn < Server

    def start_cmd
      "cd #{app.current_path} && #{@bin} -D -E #{Sunshine.deploy_env} -p #{@port} -c #{@config_file_path}"
    end

    def stop_cmd
      cmd = "(test -f #{@pid} && kill -QUIT `cat #{@pid}`) || true; "
      cmd << "sleep 2 ; rm -f #{@pid}; "
      cmd << "pkill -9 -f '#{app.current_path}/.*/#{File.basename(@pid)}'"
    end

    def setup_deploy_servers(&block)
      super do |deploy_server|
        deploy_server.run "gem install #{@name}"
        yield(deploy_server) if block_given?
      end
    end

  end

end
