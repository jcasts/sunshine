module Sunshine

  class Nginx < Server

    def initialize(app, options={})
      super
      @log_files = {:impressions => "#{@log_path}/impressions.log",
                    :stderr => "#{@log_path}/error.log",
                    :stdout => "#{@log_path}/access.log"}
    end

    def start_cmd
      "/home/ypc/sbin/nginx -c #{@config_path}"
    end

    def stop_cmd
      cmd = "test -f #{@pid} && kill -QUIT `cat #{@pid}`;"
      cmd << "sleep 2 ; rm -f #{@pid};"
      cmd << "pkill -9 -f '/#{app.current_path}/.*/nginx'"
    end


    def setup_deploy_servers(&block)
      super do |deploy_server|
        deploy_server.upload("#{CONFIG_DIR}/nginx_proxy.conf", "#{@config_path}/nginx_proxy.conf")
        deploy_server.upload("#{CONFIG_DIR}/nginx_optimize.conf", "#{@config_path}/nginx_optimize.conf")
        yield(deploy_server) if block_given?
      end
    end

  end

end
