module Sunshine

  class Server

    CONFIG_DIR = "server_configs"

    attr_reader :app, :name, :pid, :log_files, :config_template, :config_path, :config_file_path
    attr_reader :restart_cmd, :start_cmd, :stop_cmd, :bin
    attr_reader :server_name, :port, :processes, :target

    def initialize(app, options={})
      @app = app
      @name = self.class.to_s.split("::").last.downcase
      @pid = options[:pid] || "#{@app.shared_path}/pids/#{@name}.pid"
      @bin = options[:bin] || @name

      @log_path = options[:log_path] || "#{@app.shared_path}/log"
      @log_files = {
        :stderr => (options[:stderr_log] || "#{@log_path}/#{@name}_stderr.log"),
        :stdout => (options[:stdout_log] || "#{@log_path}/#{@name}_stdout.log")
      }

      @config_template = options[:config_template] || "server_configs/#{@name}.conf.erb"
      @config_path = options[:config_path] || "#{@app.current_path}/server_config"
      @config_file_path = "#{@config_path}/#{@name}.conf"

      @restart_cmd = nil

      @server_name = options[:server_name]
      @port = options[:port] || 80
      @processes = options[:processes] || 1
      @target = options[:point_to] || @app
    end

    def setup_deploy_servers(&block)
      Sunshine.info @name, "Setting up #{@name} server"
      @app.deploy_servers.each do |deploy_server|
        Sunshine::Dependencies.install @name, :console => proc{|str| deploy_server.run(str)} if Sunshine::Dependencies[@name]
        deploy_server.run "mkdir -p #{@config_path}"
        server_name = @server_name || deploy_server.host
        deploy_server.make_file!(@config_file_path, build_server_config(binding))
        yield(deploy_server) if block_given?
      end
    end

    def start(&block)
      setup_deploy_servers
      Sunshine.info @name, "Starting #{@name} server"
      @app.deploy_servers.each do |deploy_server|
        deploy_server.run(start_cmd)
        yield(deploy_server) if block_given?
      end
    end

    def stop(&block)
      Sunshine.info @name, "Stopping #{@name} server"
      @app.deploy_servers.each do |deploy_server|
        deploy_server.run(stop_cmd)
        yield(deploy_server) if block_given?
      end
    end

    def restart
      if restart_cmd
        @app.deploy_servers.run(restart_cmd)
      else
        stop
        start
      end
    end

    private

    def build_server_config(custom_binding=nil)
      str = File.read(@config_template)
      ERB.new(str, nil, '-').result(custom_binding || binding)
    end

    def start_cmd
      raise "'start_cmd' must be implemented by child class"
    end

    def stop_cmd
      raise "'stop_cmd' must be implemented by child class"
    end

  end

end
