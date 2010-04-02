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
      [:app, :name, :bin, :pid, :processes, :config_path, :log_file, :timeout]
    end


    ##
    # Returns the short, snake-case version of the class:
    #   Sunshine::Daemon.short_name
    #   #=> "daemon"

    def self.short_name
      @short_name ||= self.underscore self.to_s.split("::").last
    end


    ##
    # Turn camelcase into underscore. Used for Daemon#name.

    def self.underscore str
      str.gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
       gsub(/([a-z\d])([A-Z])/,'\1_\2').downcase
    end


    attr_reader :app, :name

    attr_accessor :bin, :pid, :processes, :timeout, :sudo, :server_apps

    attr_accessor :config_template, :config_path, :config_file

    attr_writer :start_cmd, :stop_cmd, :restart_cmd, :status_cmd


    # Daemon objects need only an App object to be instantiated but many options
    # are available for customization:
    #
    # :bin:: bin_path - Set the daemon app bin path (e.g. usr/local/nginx)
    # defaults to svr_name.
    #
    # :processes:: prcss_num - Number of processes daemon should run;
    # defaults to 1.
    #
    # :config_file:: name - Remote file name the daemon should load;
    # defaults to svr_name.conf
    #
    # :config_path:: path - Remote path daemon configs will be uploaded to;
    # defaults to app.current_path/daemons/svr_name
    #
    # :config_template:: path - Glob path to tempates to render and upload;
    # defaults to sunshine_path/templates/svr_name/*
    #
    # :log_path:: path - Path to where the log files should be output;
    # defaults to app.log_path.
    #
    # :pid:: pid_path - Set the pid; default: app.shared_path/pids/svr_name.pid
    # defaults to app.shared_path/pids/svr_name.pid.
    #
    # :sudo:: bool|str - Define if sudo should be used to run the daemon,
    # and/or with what user.
    #
    # :timeout:: int - Timeout to use for daemon config, defaults to 0.
    #
    # The Daemon constructor also supports any App#find options to narrow
    # the server apps to use. Note: subclasses such as Server already have
    # a default :role that can be overridden.

    def initialize app, options={}
      @options = options
      @app     = app

      @name        = options[:name] || self.class.short_name
      @pid         = options[:pid]  || "#{@app.shared_path}/pids/#{@name}.pid"
      @bin         = options[:bin]  || self.class.short_name
      @sudo        = options[:sudo]
      @timeout     = options[:timeout]   || 0
      @dep_name    = options[:dep_name]  || self.class.short_name
      @processes   = options[:processes] || 1
      @sigkill     = 'QUIT'

      @config_template = options[:config_template] ||
        "#{Sunshine::ROOT}/templates/#{self.class.short_name}/*"

      @config_path     = options[:config_path] ||
        "#{@app.current_path}/daemons/#{@name}"

      @config_file = options[:config_file] || "#{self.class.short_name}.conf"

      log_path  = options[:log_path] || @app.log_path
      @log_files = {
        :stderr => "#{log_path}/#{@name}_stderr.log",
        :stdout => "#{log_path}/#{@name}_stdout.log"
      }

      @start_cmd = @stop_cmd = @restart_cmd = @status_cmd = nil

      @setup_successful = nil

      register_after_user_script
    end


    ##
    # Do something with each server app used by the daemon.

    def each_server_app(&block)
      @app.each(@options, &block)
    end


    ##
    # Setup the daemon, parse and upload config templates.
    # If a dependency with the daemon name exists in Sunshine.dependencies,
    # setup will attempt to install the dependency before uploading configs.
    # If a block is given it will be passed each server_app and binder object
    # which will be used for the building erb config templates.
    # See the ConfigBinding class for more information.

    def setup
      Sunshine.logger.info @name, "Setting up #{@name} daemon" do

        each_server_app do |server_app|

          # Build erb binding
          binder = config_binding server_app.shell

          configure_remote_dirs server_app.shell
          touch_log_files server_app.shell

          yield(server_app, binder) if block_given?

          server_app.install_deps @dep_name if
            Sunshine.dependencies.exist?(@dep_name)

          upload_config_files(server_app.shell, binder.get_binding)
        end
      end

      @setup_successful = true

    rescue => e
      raise CriticalDeployError.new(e, "Could not setup #{@name}")
    end


    ##
    # Check if setup was run successfully.

    def has_setup? force=false
      return @setup_successful unless @setup_successful.nil? || force

      each_server_app do |server_app|

        unless server_app.shell.file? config_file_path
          return @setup_successful = false
        end
      end

      @setup_successful = true
    end


    ##
    # Start the daemon app after running setup.

    def start
      self.setup unless has_setup?
      Sunshine.logger.info @name, "Starting #{@name} daemon" do

        each_server_app do |server_app|
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
    # Check if the daemon is running on all servers

    def status
      each_server_app do |server_app|
        server_app.shell.call status_cmd, :sudo => pick_sudo(server_app.shell)
      end
      true

    rescue CmdError => e
      false
    end


    ##
    # Stop the daemon app.

    def stop
      Sunshine.logger.info @name, "Stopping #{@name} daemon" do

        each_server_app do |server_app|
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
      self.setup unless has_setup?

      Sunshine.logger.info @name, "Restarting #{@name} daemon" do
        each_server_app do |server_app|
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
    # Default daemon stop command.

    def stop_cmd
      "test -f #{@pid} && kill -#{@sigkill} $(cat #{@pid}) && sleep 1 && "+
        "rm -f #{@pid} || echo 'Could not kill #{@name} pid for #{@app.name}';"
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

    def log_files hash
      @log_files.merge!(hash)
    end


    ##
    # Get the path of a log file:
    #  daemon.log_file(:stderr)
    #  #=> "/all_logs/stderr.log"

    def log_file key
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

    def upload_config_files shell, setup_binding=binding
      config_template_files.each do |config_file|

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


    ##
    # Create and setup a binding for a given shell.

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


    ##
    # Pick which sudo to use between the daemon sudo and shell sudo.
    # (Useful when running servers on ports < 1024)

    def pick_sudo shell
      self.sudo.nil? ? shell.sudo : self.sudo
    end


    ##
    # Make sure all the remote directories needed by the daemon exist.

    def configure_remote_dirs shell
      dirs = @log_files.values.map{|f| File.dirname(f)}

      dirs << File.dirname(@pid)
      dirs << @config_path
      dirs.delete_if{|d| d == "."}
      dirs = dirs.join(" ")

      shell.call "mkdir -p #{dirs}"
    end


    ##
    # Make sure log files are owned by the daemon's user.

    def touch_log_files shell
      files = @log_files.values.join(" ")

      sudo = pick_sudo(shell)
      user = case sudo
             when true then 'root'
             when String then sudo
             else
               nil
             end

      shell.call "touch #{files}", :sudo => true
      shell.call "chown #{user} #{files}", :sudo => true if user
    end


    ##
    # Setup what should be run after the user block on App#deploy.

    def register_after_user_script
      @app.after_user_script do |app|
        next unless has_setup?

        each_server_app do |sa|
          sudo = pick_sudo sa.shell

          %w{start stop restart status}.each do |script|
            script_file = "#{@config_path}/#{script}"

            cmd = send "#{script}_cmd".to_sym

            sa.shell.make_file script_file, cmd,
              :flags => '--chmod=ugo=rwx'


            cmd = sa.shell.sudo_cmd script_file, sudo

            sa.scripts[script.to_sym] << [*cmd].join(" ")
          end
        end
      end
    end
  end
end
