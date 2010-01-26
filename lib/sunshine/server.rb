module Sunshine

  ##
  # An abstract class to wrap simple server software setup and start/stop.
  #
  # Child classes are expected to at least provide a start and stop bash script
  # by either overloading the start_cmd and stop_cmd methods, or by setting
  # @start_cmd and @stop_cmd. A restart_cmd method or @restart_cmd attribute
  # may also be specified if restart requires more functionality than simply
  # calling start_cmd && stop_cmd.

  class Server

    attr_reader :app, :name, :target

    attr_accessor :bin, :pid, :server_name, :port, :processes, :deploy_servers
    attr_accessor :config_template, :config_path, :config_file

    # Server objects need only an App object to be instantiated but many options
    # are available for customization:
    #
    # :point_to:: app|server - set the server target; any app or server object
    #                          defaults to the app passed to the constructor
    #
    # :pid:: pid_path - set the pid; default: app.shared_path/pids/svr_name.pid
    #                   defaults to app.shared_path/pids/svr_name.pid
    #
    # :bin:: bin_path - set the server app bin path (e.g. usr/local/nginx)
    #                   defaults to svr_name
    #
    # :port:: port_num - the port to run the server on
    #                    defaults to 80
    #
    # :processes:: prcss_num - number of processes server should run
    #                          defaults to 1
    #
    # :server_name:: myserver.com - host name used by server
    #                               defaults to nil
    #
    # :deploy_servers:: ds_arr - deploy servers to use
    #                            defaults to app's :web role servers
    #
    # :config_template:: path - glob path to tempates to render and upload
    #                           defaults to sunshine_path/templates/svr_name/*
    #
    # :config_path:: path - remote path server configs will be uploaded to
    #                       defaults to app.current_path/server_configs/svr_name
    #
    # :config_file:: name - remote file name the server should load
    #                       defaults to svr_name.conf
    #
    # :log_path:: path - path to where the log files should be output
    #                    defaults to app.log_path

    def initialize app, options={}
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
        :stderr => "#{log_path}/#{@name}_stderr.log",
        :stdout => "#{log_path}/#{@name}_stdout.log"
      }

      @start_cmd = @stop_cmd = @restart_cmd = nil

      register_after_user_script
    end


    ##
    # Setup the server app, parse and upload config templates.
    # If a dependency with the server name exists in Sunshine::Dependencies,
    # setup will attempt to install the dependency before uploading configs.

    def setup
      Sunshine.logger.info @name, "Setting up #{@name} server" do

        @deploy_servers.each do |deploy_server|

          begin
            @app.install_deps @name, :server => deploy_server
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
      raise FatalDeployError.new(e, "Could not setup #{@name}")
    end


    ##
    # Start the server app after running setup.

    def start
      self.setup
      Sunshine.logger.info @name, "Starting #{@name} server" do

        @deploy_servers.each do |deploy_server|
          begin
            deploy_server.run(start_cmd)
            yield(deploy_server) if block_given?
          rescue => e
            raise FatalDeployError.new(e, "Could not start #{@name}")
          end
        end
      end
    end


    ##
    # Stop the server app.

    def stop
      Sunshine.logger.info @name, "Stopping #{@name} server" do

        @deploy_servers.each do |deploy_server|
          begin
            deploy_server.run(stop_cmd)
            yield(deploy_server) if block_given?
          rescue => e
            raise FatalDeployError.new(e, "Could not stop #{@name}")
          end
        end
      end
    end


    ##
    # Restarts the server using the restart_cmd attribute if provided.
    # If restart_cmd is not provided, calls stop and start.

    def restart
      if restart_cmd
        self.setup
        begin
          @deploy_servers.run(@restart_cmd)
        rescue => e
          raise FatalDeployError.new(e, "Could not stop #{@name}")
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
        raise(CriticalDeployError, "@start_cmd undefined. Can't start #{@name}")
    end


    ##
    # Gets the command that stops the server.
    # Should be overridden by child classes.

    def stop_cmd
      return @stop_cmd ||
        raise(CriticalDeployError, "@stop_cmd undefined. Can't stop #{@name}")
    end


    ##
    # Gets the command that restarts the server.

    def restart_cmd
      @restart_cmd
    end


    ##
    # Append or override server log file paths:
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
    # Get the file path to the server's config file.

    def config_file_path
      "#{@config_path}/#{@config_file}"
    end


    ##
    # Upload config files and run them through erb with the provided
    # binding if necessary.

    def upload_config_files(deploy_server, setup_binding=binding)
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

    def register_after_user_script
      @app.after_user_script do |app|
        app.scripts[:start]  << self.start_cmd
        app.scripts[:stop]   << self.stop_cmd
        app.scripts[:status] << "test -f #{@pid}"

        if self.restart_cmd
          app.scripts[:restart] << self.restart_cmd
        else
          app.scripts[:restart] << self.stop_cmd
          app.scripts[:restart] << self.start_cmd
        end

        app.info[:ports] ||= {}
        app.info[:ports][@pid] = @port
      end
    end
  end
end
