module Sunshine

  class Unicorn < Server

    def start_cmd
      "cd #{app.current_path} && unicorn -D -E #{Sunshine.deploy_env} -p #{@port} -c #{@config_file_path}"
    end

    def stop_cmd
      cmd = "(test -f #{@pid_file} && kill -QUIT `cat #{@pid_file}`) || true"
      cmd << "sleep 2 ; rm -f #{@pid_file}"
      cmd << "pkill -9 -f '#{app.current_path}/.*/#{@pid_file}'"
    end

    def setup_deploy_servers(&block)
      super do |deploy_server|
        deploy_server.run "gem install #{self.name}"
        yield(deploy_server) if block_given?
      end
    end

  end

end
