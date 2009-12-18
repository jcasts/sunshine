module Sunshine

  class Server

    attr_reader :app, :name, :target

    attr_accessor :bin, :pid, :server_name, :port, :processes, :deploy_servers
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
      @deploy_servers = options[:deploy_servers] ||
        @app.deploy_servers.find(:role => :web)

      @config_template = options[:config_template] || "templates/#{@name}/*"
      @config_path     = options[:config_path] ||
        "#{@app.current_path}/server_configs/#{@name}"
      @config_file     = options[:config_file] || "#{@name}.conf"

      log_path  = options[:log_path] || @app.log_path
      @log_files = {
        :stderr => (options[:stderr_log] || "#{log_path}/#{@name}_stderr.log"),
        :stdout => (options[:stdout_log] || "#{log_path}/#{@name}_stdout.log")
      }
    end

    ##
    # Setup the server app, parse and upload config templates,
    # and install dependencies.
    def setup(&block)
      Sunshine.logger.info @name, "Setting up #{@name} server" do

        @deploy_servers.each do |deploy_server|

          begin
            Sunshine::Dependencies.install @name, :call => deploy_server
          rescue => e
            raise DependencyError,
             "Failed installing dependency #{@name} => #{e.class}: #{e.message}"
          end if Sunshine::Dependencies.exist?(@name)

          # Pass server_name to binding
          server_name = @server_name || deploy_server.host

          deploy_server.run "mkdir -p #{remote_dirs.join(" ")}"

          yield(deploy_server) if block_given?

          self.upload_config_files(deploy_server, binding)

        end

      end

    rescue => e
      raise FatalDeployError, "Could not setup server #{@name}:\n#{e.message}"
    end

    ##
    # Start the server app after running setup.
    def start(&block)
      self.setup
      Sunshine.logger.info @name, "Starting #{@name} server" do

        @deploy_servers.each do |deploy_server|
          begin
            deploy_server.run(start_cmd)
            yield(deploy_server) if block_given?
          rescue => e
            raise FatalDeployError,
              "Could not start server #{@name}:\n#{e.message}"
          end
        end

      end
    end

    ##
    # Stop the server app.
    def stop(&block)
      Sunshine.logger.info @name, "Stopping #{@name} server" do

        @deploy_servers.each do |deploy_server|
          begin
            deploy_server.run(stop_cmd)
            yield(deploy_server) if block_given?
          rescue => e
            raise FatalDeployError,
              "Could not stop server #{@name}:\n#{e.message}"
          end
        end

      end
    end

    ##
    # Restarts the server using the restart_cmd attribute if provided.
    # If restart_cmd is not provided, calls stop and start.
    def restart
      if @restart_cmd
        self.setup
        begin
          @deploy_servers.run(@restart_cmd)
        rescue => e
          raise FatalDeployError,
            "Could not stop server #{@name}:\n#{e.message}"
        end
      else
        self.stop
        self.start
      end
    end

    ##
    # Gets the command that starts the server.
    # Should be overridden by child classes.
    def start_cmd
      return @start_cmd ||
        raise(FatalDeployError, "@start_cmd is undefined. Can't start #{@name}")
    end

    ##
    # Gets the command that stops the server.
    # Should be overridden by child classes.
    def stop_cmd
      return @stop_cmd ||
        raise(FatalDeployError, "@stop_cmd is undefined. Can't stop #{@name}")
    end

    ##
    # Gets the command that restarts the server.
    def restart_cmd
      @restart_cmd
    end

    ##
    # Append or override server log files:
    #   server.log_files :stderr => "/all_logs/stderr.log"
    def log_files(hash)
      @log_files.merge!(hash)
    end

    ##
    # Get the path of a log file:
    #  server.log_file(:stderr)
    #  #=> "/all_logs/stderr.log"
    def log_file(key)
      @log_files[key]
    end

    ##
    # Get the file path to the server's config file
    def config_file_path
      "#{@config_path}/#{@config_file}"
    end

    ##
    # Upload config files and run them through erb with the provided
    # binding if necessary.
    def upload_config_files(deploy_server, setup_binding)
      self.config_template_files.each do |config_file|
        if File.extname(config_file) == ".erb"
          filename = File.basename(config_file[0..-5])
          parsed_config = @app.build_erb(config_file, setup_binding)
          deploy_server.make_file "#{@config_path}/#{filename}", parsed_config
        else
          filename = File.basename(config_file)
          deploy_server.upload config_file, "#{@config_path}/#{filename}"
        end
      end
    end

    ##
    # Get the array of local config template files needed by the server.
    def config_template_files
      @config_template_files ||= Dir[@config_template].select{|f| File.file?(f)}
    end


    private

    def remote_dirs
      dirs = @log_files.values.map{|f| File.dirname(f)}
      dirs.concat [@config_path, File.dirname(@pid)]
      dirs.delete_if{|d| d == "."}
      dirs
    end

  end

end
