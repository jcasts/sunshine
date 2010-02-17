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

    BINDER_METHODS = [
      :app, :name, :target, :bin, :pid, :server_name, :port,
      :processes, :config_path, :log_file, :timeout
    ]


    ##
    # Turn camelcase into underscore. Used for server.name.

    def self.underscore str
      str.gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
       gsub(/([a-z\d])([A-Z])/,'\1_\2').downcase
    end


    attr_reader :app, :name, :target, :server_name

    attr_accessor :bin, :pid, :port, :processes, :timeout,
                  :sudo, :deploy_servers

    attr_accessor :config_template, :config_path, :config_file

    attr_writer :start_cmd, :stop_cmd, :restart_cmd


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
    # :sudo:: bool|str - define if sudo should be used and with what user
    #
    # :timeout:: int|str - timeout to use for server config
    #                      defaults to 1
    #
    # :processes:: prcss_num - number of processes server should run
    #                          defaults to 0
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
      @name   = self.class.underscore self.class.to_s.split("::").last

      @pid         = options[:pid] || "#{@app.shared_path}/pids/#{@name}.pid"
      @bin         = options[:bin] || @name
      @port        = options[:port] || 80
      @sudo        = options[:sudo]
      @timeout     = options[:timeout] || 0
      @dep_name    = options[:dep_name] || @name
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
    # If a block is given it will be passed each deploy_server and binder object
    # which will be used for the building erb config templates.
    # See the ConfigBinding class for more information.

    def setup
      Sunshine.logger.info @name, "Setting up #{@name} server" do

        @deploy_servers.each do |deploy_server|

          begin
            @app.install_deps @dep_name, :server => deploy_server
          rescue => e
            raise DependencyError.new(e,
              "Failed installing dependency #{@dep_name}")
          end if Sunshine::Dependencies.exist?(@dep_name)

          # Pass server_name to binding

          binder = config_binding deploy_server

          deploy_server.call "mkdir -p #{remote_dirs.join(" ")}",
            :sudo => binder.sudo

          yield(deploy_server, binder) if block_given?

          self.upload_config_files(deploy_server, binder.get_binding)
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
            deploy_server.call start_cmd, :sudo => pick_sudo(deploy_server)

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
            deploy_server.call stop_cmd, :sudo => pick_sudo(deploy_server)

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

        Sunshine.logger.info @name, "Starting #{@name} server" do
          begin
            @deploy_servers.each do |deploy_server|
              deploy_server.call @restart_cmd, :sudo => pick_sudo(deploy_server)
            end

          rescue => e
            raise FatalDeployError.new(e, "Could not restart #{@name}")
          end
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

    def config_binding deploy_server
      binder = Binder.new self
      binder.forward(*BINDER_METHODS)

      binder.set :deploy_server, deploy_server
      binder.set :server_name,   (@server_name || deploy_server.host)

      binder_sudo = pick_sudo(deploy_server)
      binder.set :sudo, binder_sudo

      binder.set :expand_path do |path|
        deploy_server.expand_path path
      end

      binder
    end

    def pick_sudo deploy_server
      case deploy_server.sudo
      when true
        self.sudo || deploy_server.sudo
      when String
        String === self.sudo ? self.sudo : deploy_server.sudo
      else
        self.sudo
      end
    end

    def remote_dirs
      dirs = @log_files.values.map{|f| File.dirname(f)}
      dirs.concat [@config_path, File.dirname(@pid)]
      dirs.delete_if{|d| d == "."}
      dirs
    end

    def register_after_user_script
      @app.after_user_script do |app|
        app.scripts[:start]  << start_cmd
        app.scripts[:stop]   << stop_cmd
        app.scripts[:status] << "test -f #{@pid}"

        restart = restart_cmd ? restart_cmd : [stop_cmd, start_cmd]
        app.scripts[:restart].concat [*restart]

        app.info[:ports][@pid] = @port
      end
    end
  end
end
