module Sunshine

  class Server

    CONFIG_DIR = "../server_configs"

    attr_reader :app, :name, :pid, :log_files, :config_template

    def initialize(app, options={})
      @app = app
      @name ||= self.class.to_s.split("::").last.downcase
      @pid = options[:pid] || "#{@app.shared_path}/pids/#{@name}.pid"

      @log_path = options[:log_path] || "#{@app.shared_path}/log"
      @log_files = {
        :stderr => (options[:stderr_log] || "#{@log_path}/#{@name}_stderr.log"),
        :stdout => (options[:stdout_log] || "#{@log_path}/#{@name}_stdout.log")
      }

      @config_template = options[:config_template] || "../server_configs/#{@name}.conf.erb"
      @config_path = options[:config_path] || "#{@app.current_path}/server_config"
      @config_file_path = "#{@config_path}/#{@name}.conf"
    end

    def setup_deploy_servers(&block)
      @app.deploy_servers.each do |deploy_server|
        deploy_server.make_file!(@config_file_path, server_config)
        yield(deploy_server) if block_given?
      end
    end

    def server_config(force=false)
      @server_config = build_server_config if !@server_config || force
    end

    def start(&block)
      @app.deploy_servers.each do |deploy_server|
        deploy_server.run(start_cmd)
        yield(deploy_server) if block_given?
      end
    end

    def stop(&block)
      @app.deploy_servers.each do |deploy_server|
        deploy_server.run(stop_cmd)
        yield(deploy_server) if block_given?
      end
    end

    def restart
      stop
      start
    end

    private

    def build_server_config
      str = File.read(@config_template)
      ERB.new(str, nil, '-').result(@app.runtime_binding)
    end

    def start_cmd
      raise "'start_cmd' must be implemented by child class"
    end

    def stop_cmd
      raise "'stop_cmd' must be implemented by child class"
    end

  end

end
