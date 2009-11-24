module Sunshine

  class Server

    TEMPLATES_DIR = "server_configs"

    attr_reader :app, :name, :target

    attr_accessor :bin, :pid, :server_name, :port, :processes
    attr_accessor :config_template, :config_path, :config_file

    def initialize(app, options={})
      @app    = app
      @target = options[:point_to] || @app
      @name   = self.class.to_s.split("::").last.downcase

      @pid         = options[:pid] || "#{@app.shared_path}/pids/#{@name}.pid"
      @bin         = options[:bin] || @name
      @port        = options[:port] || 80
      @processes   = options[:processes] || 1
      @server_name = options[:server_name]

      @config_template = options[:config_template] || "#{TEMPLATES_DIR}/#{@name}.conf.erb"
      @config_path     = options[:config_path] || "#{@app.current_path}/server_config"
      @config_file     = options[:config_file] || "#{@name}.conf"

      log_path  = options[:log_path] || "#{@app.shared_path}/log"
      @log_files = {
        :stderr => (options[:stderr_log] || "#{log_path}/#{@name}_stderr.log"),
        :stdout => (options[:stdout_log] || "#{log_path}/#{@name}_stdout.log")
      }
    end

    def setup(&block)
      Sunshine.logger.info @name, "Setting up #{@name} server" do

        @app.deploy_servers.each do |deploy_server|

          begin
            Sunshine::Dependencies.install @name,
              :console => deploy_server
          rescue => e
            raise DependencyError,
                  "Could not install dependency #{@name} => #{e.class}: #{e.message}"
          end if Sunshine::Dependencies.exist?(@name)

          server_name = @server_name || deploy_server.host # Pass server_name to binding

          deploy_server.run "mkdir -p #{remote_dirs.join(" ")}"

          yield(deploy_server) if block_given?

          deploy_server.make_file self.config_file_path, build_server_config(binding)

        end

      end

    rescue => e
      raise FatalDeployError, "Could not setup server #{@name}:\n#{e.message}"
    end

    def start(&block)
      self.setup
      Sunshine.logger.info @name, "Starting #{@name} server" do

        @app.deploy_servers.each do |deploy_server|
          begin
            deploy_server.run(start_cmd)
            yield(deploy_server) if block_given?
          rescue => e
            raise FatalDeployError, "Could not start server #{@name}:\n#{e.message}"
          end
        end

      end
    end

    def stop(&block)
      Sunshine.logger.info @name, "Stopping #{@name} server" do

        @app.deploy_servers.each do |deploy_server|
          begin
            deploy_server.run(stop_cmd)
            yield(deploy_server) if block_given?
          rescue => e
            raise FatalDeployError, "Could not stop server #{@name}:\n#{e.message}"
          end
        end

      end
    end

    def restart
      if @restart_cmd
        self.setup
        begin
          @app.deploy_servers.run(@restart_cmd)
        rescue => e
          raise FatalDeployError, "Could not stop server #{@name}:\n#{e.message}"
        end
      else
        self.stop
        self.start
      end
    end

    def start_cmd
      return @start_cmd || raise(FatalDeployError, "'start_cmd' is undefined. Cannot start #{@name}")
    end

    def stop_cmd
      return @stop_cmd || raise(FatalDeployError, "'stop_cmd' is undefined. Cannot stop #{@name}")
    end

    def restart_cmd
      @restart_cmd
    end

    def log_files(hash)
      @log_files.merge!(hash)
    end

    def log_file(key)
      @log_files[key]
    end

    def config_file_path
      "#{@config_path}/#{@config_file}"
    end

    private

    def remote_dirs
      dirs = @log_files.values.map{|f| File.dirname(f)}
      dirs.concat [@config_path, File.dirname(@pid)]
      dirs.delete_if{|d| d == "."}
      dirs
    end

    def build_server_config(custom_binding=nil)
      str = File.read(@config_template)
      ERB.new(str, nil, '-').result(custom_binding || binding)
    end

  end

end
