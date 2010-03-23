module Sunshine

  ##
  # Simple server wrapper for nginx setup and control.

  class Nginx < Server

    def initialize app, options={}
      super

      @sudo = options[:sudo] || @port < 1024

      @dep_name = options[:dep_name] ||
        use_passenger? ? 'passenger-nginx' : 'nginx'
    end


    def start_cmd
      "#{@bin} -c #{self.config_file_path}"
    end


    def stop_cmd
      cmd = "test -f #{@pid} && kill -QUIT $(cat #{@pid})"+
        " || echo 'No #{@name} process to stop for #{@app.name}';"
      cmd << "sleep 2 ; rm -f #{@pid};"
    end


    def setup
      super do |server_app, binder|

        binder.set :nginx_conf_path do
          nginx_bin = server_app.shell.call "which nginx"
          File.join File.dirname(nginx_bin), '..', 'conf'
        end

        yield(server_app, binder) if block_given?
      end
    end
  end
end
