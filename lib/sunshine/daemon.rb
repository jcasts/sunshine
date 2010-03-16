module Sunshine

  ##
  # An abstract class to wrap simple daemon software setup and start/stop.
  #
  # Child classes are expected to at least provide a start and stop bash script
  # by either overloading the start_cmd and stop_cmd methods, or by setting
  # @start_cmd and @stop_cmd. A restart_cmd method or @restart_cmd attribute
  # may also be specified if restart requires more functionality than simply
  # calling start_cmd && stop_cmd.

  class Daemon


    ##
    # Returns an array of method names to assign to the binder
    # for template rendering.

    def self.binder_methods
      [:app, :name, :target, :bin, :pid, :port,
      :processes, :config_path, :log_file, :timeout]
    end


    ##
    # Turn camelcase into underscore. Used for Daemon#name.

    def self.underscore str
      str.gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
       gsub(/([a-z\d])([A-Z])/,'\1_\2').downcase
    end


    attr_reader :app, :name, :target

    attr_accessor :bin, :pid, :processes, :timeout, :sudo, :server_apps

    attr_accessor :config_template, :config_path, :config_file

    attr_writer :start_cmd, :stop_cmd, :restart_cmd, :status_cmd


    # Daemon objects need only an App object to be instantiated but many options
    # are available for customization:
    #
    # :pid:: pid_path - set the pid; default: app.shared_path/pids/svr_name.pid
    #                   defaults to app.shared_path/pids/svr_name.pid
    #
    # :bin:: bin_path - set the daemon app bin path (e.g. usr/local/nginx)
    #                   defaults to svr_name
    #
    # :sudo:: bool|str - define if sudo should be used and with what user
    #
    # :timeout:: int|str - timeout to use for daemon config
    #                      defaults to 1
    #
    # :processes:: prcss_num - number of processes daemon should run
    #                          defaults to 0
    #
    # :server_apps:: ds_arr - deploy servers to use
    #
    # :config_template:: path - glob path to tempates to render and upload
    #                           defaults to sunshine_path/templates/svr_name/*
    #
    # :config_path:: path - remote path daemon configs will be uploaded to
    #                       defaults to app.current_path/daemons/svr_name
    #
    # :config_file:: name - remote file name the daemon should load
    #                       defaults to svr_name.conf
    #
    # :log_path:: path - path to where the log files should be output
    #                    defaults to app.log_path
    #
    # :point_to:: app|daemon - an abstract target to point to
    #                                 defaults to the passed app

    def initialize app, options={}
      @app    = app
      @target = options[:point_to] || @app
      @name   = self.class.underscore self.class.to_s.split("::").last

      @pid         = options[:pid] || "#{@app.shared_path}/pids/#{@name}.pid"
      @bin         = options[:bin] || @name
      @sudo        = options[:sudo]
      @timeout     = options[:timeout] || 0
      @dep_name    = options[:dep_name] || @name
      @processes   = options[:processes] || 1

      @server_apps =
        options[:server_apps] || @app.server_apps

      @config_template = options[:config_template] || "templates/#{@name}/*"
      @config_path     = options[:config_path] ||
        "#{@app.current_path}/daemons/#{@name}"
      @config_file     = options[:config_file] || "#{@name}.conf"

      log_path  = options[:log_path] || @app.log_path
      @log_files = {
        :stderr => "#{log_path}/#{@name}_stderr.log",
        :stdout => "#{log_path}/#{@name}_stdout.log"
      }


      @start_cmd = @stop_cmd = @restart_cmd = @status_cmd = nil


      register_after_user_script
    end


    ##
    # Setup the daemon, parse and upload config templates.
    # If a dependency with the daemon name exists in Sunshine::Dependencies,
    # setup will attempt to install the dependency before uploading configs.
    # If a block is given it will be passed each server_app and binder object
    # which will be used for the building erb config templates.
    # See the ConfigBinding class for more information.

    def setup
      Sunshine.logger.info @name, "Setting up #{@name} daemon" do

        @server_apps.each do |server_app|

          begin
            server_app.install_deps @dep_name
          rescue => e
            raise DependencyError.new(e,
              "Failed installing dependency #{@dep_name}")
          end if Sunshine::Dependencies.exist?(@dep_name)

          # Build erb binding
          binder = config_binding server_app.shell

          server_app.shell.call "mkdir -p #{remote_dirs.join(" ")}",
            :sudo => binder.sudo

          yield(server_app, binder) if block_given?

          self.upload_config_files(server_app.shell, binder.get_binding)
        end
      end

    rescue => e
      raise CriticalDeployError.new(e, "Could not setup #{@name}")
    end


    ##
    # Start the daemon app after running setup.

    def start
      self.setup
      Sunshine.logger.info @name, "Starting #{@name} daemon" do

        @server_apps.each do |server_app|
          begin
            server_app.shell.call start_cmd,
              :sudo => pick_sudo(server_app.shell)

            yield(server_app) if block_given?
          rescue => e
            raise CriticalDeployError.new(e, "Could not start #{@name}")
          end
        end
      end
    end


    ##
    # Stop the daemon app.

    def stop
      Sunshine.logger.info @name, "Stopping #{@name} daemon" do

        @server_apps.each do |server_app|
          begin
            server_app.shell.call stop_cmd,
              :sudo => pick_sudo(server_app.shell)

            yield(server_app) if block_given?
          rescue => e
            raise CriticalDeployError.new(e, "Could not stop #{@name}")
          end
        end
      end
    end


    ##
    # Restarts the daemon using the restart_cmd attribute if provided.
    # If restart_cmd is not provided, calls stop and start.

    def restart
      self.setup

      Sunshine.logger.info @name, "Restarting #{@name} daemon" do
        @server_apps.each do |server_app|
          begin
            server_app.shell.call restart_cmd,
              :sudo => pick_sudo(server_app.shell)

            yield(server_app) if block_given?
          rescue => e
            raise CriticalDeployError.new(e, "Could not restart #{@name}")
          end
        end
      end
    end


    ##
    # Gets the command that starts the daemon.
    # Should be overridden by child classes.

    def start_cmd
      return @start_cmd ||
        raise(CriticalDeployError, "@start_cmd undefined. Can't start #{@name}")
    end


    ##
    # Gets the command that stops the daemon.
    # Should be overridden by child classes.

    def stop_cmd
      return @stop_cmd ||
        raise(CriticalDeployError, "@stop_cmd undefined. Can't stop #{@name}")
    end


    ##
    # Gets the command that restarts the daemon.

    def restart_cmd
      @restart_cmd || [stop_cmd, start_cmd].map{|c| "(#{c})"}.join(" && ")
    end


    ##
    # Get the command to check if the daemon is running.

    def status_cmd
      @status_cmd || "test -f #{@pid}"
    end


    ##
    # Append or override daemon log file paths:
    #   daemon.log_files :stderr => "/all_logs/stderr.log"

    def log_files(hash)
      @log_files.merge!(hash)
    end


    ##
    # Get the path of a log file:
    #  daemon.log_file(:stderr)
    #  #=> "/all_logs/stderr.log"

    def log_file(key)
      @log_files[key]
    end


    ##
    # Get the file path to the daemon's config file.

    def config_file_path
      "#{@config_path}/#{@config_file}"
    end


    ##
    # Upload config files and run them through erb with the provided
    # binding if necessary.

    def upload_config_files(shell, setup_binding=binding)
      self.config_template_files.each do |config_file|

        if File.extname(config_file) == ".erb"
          filename = File.basename(config_file[0..-5])
          parsed_config = @app.build_erb(config_file, setup_binding)
          shell.make_file "#{@config_path}/#{filename}", parsed_config
        else
          filename = File.basename(config_file)
          shell.upload config_file, "#{@config_path}/#{filename}"
        end
      end
    end


    ##
    # Get the array of local config template files needed by the daemon.

    def config_template_files
      @config_template_files ||= Dir[@config_template].select{|f| File.file?(f)}
    end


    private

    def config_binding shell
      binder = Binder.new self
      binder.forward(*self.class.binder_methods)

      binder.set :shell, shell

      binder_sudo = pick_sudo(shell)
      binder.set :sudo, binder_sudo

      binder.set :expand_path do |path|
        shell.expand_path path
      end

      binder
    end


    def pick_sudo shell
      case shell.sudo
      when true
        self.sudo || shell.sudo
      when String
        String === self.sudo ? self.sudo : shell.sudo
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
        @server_apps.each do |sa|
          sa.scripts[:start]   << start_cmd
          sa.scripts[:stop]    << stop_cmd
          sa.scripts[:restart] << restart_cmd
          sa.scripts[:status]  << status_cmd
        end
      end
    end
  end
end
