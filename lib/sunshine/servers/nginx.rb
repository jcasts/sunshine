module Sunshine

  class Nginx < Server

    def start_cmd
      sudo = run_sudo? ? "sudo " : ""
      "#{sudo}#{@bin} -c #{self.config_file_path}"
    end

    def stop_cmd
      sudo = run_sudo? ? "sudo " : ""
      cmd = "test -f #{@pid} && #{sudo}kill -QUIT `cat #{@pid}`;"
      cmd << "sleep 2 ; rm -f #{@pid};"
      cmd << "#{sudo}pkill -QUIT -f '#{@app.current_path}/.*nginx';"
      cmd << "#{sudo}pkill -9 -f '#{@app.current_path}/.*nginx'"
    end

    def setup(&block)
      super do |deploy_server|
        deploy_server.upload "#{TEMPLATES_DIR}/nginx_proxy.conf",
                             "#{@config_path}/nginx_proxy.conf"

        deploy_server.upload "#{TEMPLATES_DIR}/nginx_optimize.conf",
                             "#{@config_path}/nginx_optimize.conf"

        yield(deploy_server) if block_given?
      end
    end


    private

    def run_sudo?
      @port < 1024
    end

  end

end
