module Sunshine

  class Nginx < Server

    def initialize(app, options={})
      super

      @start_cmd = "/home/ypc/sbin/nginx -c #{@config_path}"
      @stop_cmd = "test -f #{@pid} && kill -QUIT `cat #{@pid}`"
      @restart_cmd = "test -f #{@pid} && kill -HUP `cat #{@pid}` || /home/ypc/sbin/nginx -c #{@config_path}"

      @log_files = {:impressions => "#{@log_path}/impressions.log",
                    :stderr => "#{@log_path}/error.log",
                    :stdout => "#{@log_path}/access.log"}
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
