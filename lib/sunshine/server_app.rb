module Sunshine

  ##
  # Handles App deployment functionality for a single deploy server.
  #
  # Server apps can be assigned any number of roles for classification.
  # :roles:: sym|array - roles assigned (web, db, app, etc...)
  # By default server apps get the special :all role which will
  # always return true when calling:
  #   server_app.has_roles? :some_role
  #
  # ServerApp objects can be instantiated several ways:
  #   ServerApp.new app_instance, shell_instance, options_hash
  #
  # When passing an App instance, the new ServerApp will keep an active link
  # to the app's properties. Name, deploy, and path attributes will be
  # actively linked.
  #
  # Rely on ServerApp to create a RemoteShell instance to use:
  #   ServerApp.new app_instance, "host.com", options_hash
  #
  # Instantiate with app name and rely on Sunshine defaults for app paths:
  #   ServerApp.new "app_name", shell_instance, options_hash
  #
  # Explicitely assign the app's root path:
  #   ServerApp.new "app_name", ..., :root_path => "/path/to/app_root"
  #
  # Assigning a specific deploy name to use can be done with the
  # :deploy_name option:
  #   ServerApp.new "app_name", ..., :deploy_name => "deploy"

  class ServerApp


    ##
    # Define an attribute that will get a value from app, or locally if
    # @app isn't set.

    def self.app_attr *attribs
      attribs.each do |attrib|
        class_eval <<-STR, __FILE__, __LINE__ + 1
          def #{attrib}
            @app ? @app.send(:#{attrib}) : @#{attrib}
          end
        STR
      end
    end


    ##
    # Creates dependency instance methods such as gem_install, yum_install, etc
    # on both App and ServerApp classes.

    def self.register_dependency_type dep_class
      class_eval <<-STR, __FILE__, __LINE__ + 1
        def #{dep_class.short_name}_install(*names)
          options = Hash === names.last ? names.delete_at(-1) : Hash.new

          names.each do |name|
            dep = #{dep_class}.new(name, options)
            dep.install! :call => @shell
          end
        end
      STR

      App.class_eval <<-STR, __FILE__, __LINE__ + 1
        def #{dep_class.short_name}_install(*names)
          options = names.last if Hash === names.last
          with_server_apps options,
            :msg  => "Installing #{dep_class.short_name} packages",
            :send => [:#{dep_class.short_name}_install, *names]
        end
      STR
    end


    ##
    # Creates a ServerApp instance from a deploy info file.

    def self.from_info_file path, shell=nil
      shell ||= Sunshine.shell

      opts = YAML.load shell.call("cat #{path}")
      opts[:root_path] = opts.delete :path

      sa_shell = shell.dup
      sa_shell.env = opts[:env] || Hash.new
      sa_shell.connect if shell.connected?

      new opts[:name], sa_shell, opts
    end


    app_attr :name, :deploy_name
    app_attr :root_path, :checkout_path, :current_path
    app_attr :deploys_path, :log_path, :shared_path, :scripts_path

    attr_accessor :app, :roles, :scripts, :info, :shell, :crontab, :health
    attr_writer :pkg_manager

    ##
    # Create a server app instance. Supports the following
    # argument configurations:
    #
    #   ServerApp.new app_inst, "myserver.com", :roles => :web
    #   ServerApp.new "app_name", shell_inst, options_hash

    def initialize app, host, options={}

      @app = App === app ? app : nil

      name = @app && @app.name || app
      assign_local_app_attr name, options

      @deploy_details = nil

      @roles = options[:roles] || [:all]
      @roles = @roles.split(" ") if String === @roles
      @roles = [*@roles].compact.map{|r| r.to_sym }

      @scripts = Hash.new{|h, k| h[k] = []}
      @info    = {:ports => {}}

      @pkg_manager = nil

      @shell = case host
               when String then RemoteShell.new host, options
               when Shell  then host
               else
                 raise "Could not get remote shell '#{host}'"
               end

      @crontab = Crontab.new name, @shell
      @health  = Healthcheck.new shared_path, @shell

      @all_deploy_names = nil
      @previous_deploy_name = nil
    end


    ##
    # Add paths the the shell $PATH env.

    def add_shell_paths(*paths)
      path = shell_env["PATH"] || "$PATH"
      paths << path

      shell_env.merge! "PATH" => paths.join(":")
    end


    ##
    # Creates and uploads all control scripts for the application.
    # To add to, or define a control script, see App#add_to_script.

    def build_control_scripts
      @shell.call "mkdir -p #{self.scripts_path}"

      write_script "env", make_env_bash_script

      build_scripts = @scripts.dup

      if build_scripts[:restart].empty? &&
        !build_scripts[:start].empty? && !build_scripts[:stop].empty?
        build_scripts[:restart] << "#{self.root_path}/stop"
        build_scripts[:restart] << "#{self.root_path}/start"
      end

      if build_scripts[:status].empty?
        build_scripts[:status] << "echo 'No status for #{self.name}'; exit 1;"
      end

      build_scripts.each do |name, cmds|
        if cmds.empty?
          Sunshine.logger.warn @shell.host, "#{name} script is empty"
        end

        bash = make_bash_script name, cmds

        write_script name, bash
      end

      symlink_scripts_to_root
    end


    ##
    # Creates a yaml file with deploy information. To add custom information
    # to the info file, use the app's info hash attribute:
    #   app.info[:key] = "some value"

    def build_deploy_info_file

      deploy_info   = get_deploy_info.to_yaml
      info_filepath = "#{self.scripts_path}/info"

      @shell.make_file info_filepath, deploy_info

      @shell.symlink info_filepath, "#{self.root_path}/info"
    end


    ##
    # Checks out the app's codebase to the checkout path.

    def checkout_repo repo, scm_info={}
      install_deps repo.scm

      Sunshine.logger.info repo.scm,
        "Checking out to #{@shell.host} #{self.checkout_path}" do

        @info[:scm] = repo.checkout_to self.checkout_path, @shell
        @info[:scm].merge! scm_info
      end
    end


    ##
    # Get post-mortum information about the app's deploy, from the
    # generated deploy info file.
    # Post-deploy only.

    def deploy_details reload=false
      return @deploy_details if @deploy_details && !reload
      @deploy_details =
        YAML.load @shell.call("cat #{self.root_path}/info") rescue nil

      @deploy_details = nil unless Hash === @deploy_details

      @deploy_details
    end


    ##
    # Checks if the server_app's current info file deploy_name matches
    # the server_app's deploy_name attribute.

    def deployed?
      success =
        @deploy_details[:deploy_name] == self.deploy_name if @deploy_details

      return success if success

      deploy_details(true)[:deploy_name] == self.deploy_name rescue false
    end


    ##
    # An array of all directories used by the app.
    # Does not include symlinked directories.

    def directories
      [root_path, deploys_path, shared_path,
      log_path, checkout_path, scripts_path]
    end


    ##
    # Builds a hash with information about the deploy at hand.

    def get_deploy_info
      { :deployed_at => Time.now.to_s,
        :deployed_as => @shell.call("whoami"),
        :deployed_by => Sunshine.shell.user,
        :deploy_name => File.basename(self.checkout_path),
        :name        => self.name,
        :env         => shell_env,
        :roles       => @roles,
        :path        => self.root_path,
        :sunshine_version => Sunshine::VERSION
      }.merge @info
    end


    ##
    # Decrypt a file using gpg. Allows options:
    # :output:: str - the path the output file should go to
    # :passphrase:: str - the passphrase gpg should use

    def gpg_decrypt gpg_file, options={}
      output_file     = options[:output] || gpg_file.gsub(/\.gpg$/, '')

      passphrase      = options[:passphrase]
      passphrase_file = "#{self.root_path}/tmp/gpg_passphrase"

      gpg_cmd = "gpg --batch --no-tty --yes --output #{output_file} "+
        "--passphrase-file #{passphrase_file} --decrypt #{gpg_file}"

      @shell.call "mkdir -p #{File.dirname(passphrase_file)}"

      @shell.make_file passphrase_file, passphrase

      @shell.call "cd #{self.checkout_path} && #{gpg_cmd}"
      @shell.call "rm -f #{passphrase_file}"
    end


    ##
    # Check if this server app includes the specified roles:
    #   server_app.has_roles? :web
    #   server_app.has_roles? [:web, :app]
    #
    # The boolean operator may be changed to OR by passing true as the
    # second argument:
    #   server_app.roles = [:web, :app]
    #   server_app.has_roles? [:web, :db]         #=> false
    #   server_app.has_roles? [:web, :db], true   #=> true

    def has_roles? roles, match_any=false
      roles = [*roles]

      return true                     if @roles.include? :all
      return !(roles & @roles).empty? if match_any

      (roles & @roles).length == roles.length
    end


    ##
    # Install dependencies previously defined in Sunshine.dependencies.
    # Will not execute if Sunshine.auto_dependencies? is false.

    def install_deps(*deps)
      return unless Sunshine.auto_dependencies?

      options = {:call => @shell, :prefer => pkg_manager}
      options.merge! deps.delete_at(-1) if Hash === deps.last

      args = deps << options
      Sunshine.dependencies.install(*args)
    end


    ##
    # Creates the required application directories.

    def make_app_directories
      @shell.call "mkdir -p #{self.directories.join(" ")}"
    end


    ##
    # Makes an array of bash commands into a script that
    # echoes 'true' on success.

    def make_bash_script name, cmds
      cmds = cmds.map{|cmd| "(#{cmd})" }

      cmds << "echo true"

      bash = <<-STR
#!/bin/bash
if [ "$1" == "--no-env" ]; then
  #{cmds.flatten.join(" && ")}
else
  #{self.root_path}/env #{self.root_path}/#{name} --no-env
fi
      STR
    end


    ##
    # Creates the one-off env script that will be used by other scripts
    # to correctly set their env variables.

    def make_env_bash_script
      env_str = shell_env.map{|e| e.join("=")}.join(" ")
      "#!/bin/bash\nenv #{env_str} \"$@\""
    end


    ##
    # Returns the type of package management system to use.

    def pkg_manager
      @pkg_manager ||=
        DependencyLib.dependency_types.detect do |dt|
          dt.system_manager? @shell
        end
    end


    ##
    # Returns an array of all deploys in the deploys_path dir,
    # starting with the oldest.

    def all_deploy_names reload=false
      return @all_deploy_names if @all_deploy_names && !reload

      @all_deploy_names =
        @shell.call("ls -rc1 #{self.deploys_path}").split("\n")
    end


    ##
    # Returns the name of the previous deploy.

    def previous_deploy_name reload=false
      return @previous_deploy_name if @previous_deploy_name && !reload

      arr = all_deploy_names(reload)
      arr.delete(@deploy_name)

      @previous_deploy_name = arr.last
    end


    ##
    # Run a rake task the deploy server.

    def rake command
      install_deps 'rake', :type => Gem
      @shell.call "cd #{self.checkout_path} && rake #{command}"
    end


    ##
    # Adds the app to the deploy server's deployed-apps list

    def register_as_deployed
      AddCommand.exec self.root_path, 'servers' => [@shell]
    end


    ##
    # Removes old deploys from the checkout_dir
    # based on Sunshine's max_deploy_versions.

    def remove_old_deploys
      deploys = all_deploy_names true

      return unless deploys.length > Sunshine.max_deploy_versions

      lim = Sunshine.max_deploy_versions + 1

      rm_deploys = deploys[0..-lim]
      rm_deploys.map!{|d| "#{self.deploys_path}/#{d}"}

      @shell.call "rm -rf #{rm_deploys.join(" ")}"
    end


    ##
    # Run the app's restart script. Returns false on failure.
    # Post-deploy only.

    def restart
      # Permissions are handled by the script, use: :sudo => false
      run_script :stop, :sudo => false
    end


    ##
    # Run the app's restart script. Raises an exception on failure.
    # Post-deploy only.

    def restart!
      # Permissions are handled by the script, use: :sudo => false
      run_script! :restart, :sudo => false
    end


    ##
    # Symlink current directory to previous checkout and remove
    # the current deploy directory.

    def revert!
      @shell.call "rm -rf #{self.checkout_path}"

      last_deploy = previous_deploy_name(true)

      if last_deploy && !last_deploy.empty?
        @shell.symlink "#{self.deploys_path}/#{last_deploy}", self.current_path

        Sunshine.logger.info @shell.host, "Reverted to #{last_deploy}"

      else
        @crontab.delete!

        Sunshine.logger.info @shell.host, "No previous deploy to revert to."
      end
    end


    ##
    # Runs bundler. Installs the bundler gem if missing.

    def run_bundler options={}
      install_deps 'bundler', :type => Gem
      @shell.call "cd #{self.checkout_path} && gem bundle", options
    end


    ##
    # Runs geminstaller. :(
    # Deprecated: how about trying bundler or isolate?
    # If sudo is required to install to your GEM_HOME, make sure to
    # pass it as an argument:
    #   server_app.run_geminstaller :sudo => true

    def run_geminstaller options={}
      install_deps 'geminstaller', :type => Gem
      # Without sudo gems get installed to ~user/.gems
      @shell.call "cd #{self.checkout_path} && geminstaller -e", options
    end


    ##
    # Runs a script from the root_path.
    # Post-deploy only.

    def run_script name, options=nil, &block
      options ||= {}
      run_script! name, options, &block rescue false
    end


    ##
    # Runs a script from the root_path. Raises an exception if the status
    # code is not 0.
    # Post-deploy only.

    def run_script! name, options=nil, &block
      options ||= {}

      script_path = File.join self.root_path, name.to_s
      @shell.call script_path, options, &block
    end


    ##
    # Check if the app pids are present.
    # Post-deploy only.

    def running?
      # Permissions are handled by the script, use: :sudo => false
      run_script! :status, :sudo => false
      true

    rescue CmdError => e
      return false if e.exit_code == Daemon::STATUS_DOWN_CODE
      raise e
    end


    ##
    # Run a sass task on any or all deploy servers.

    def sass *sass_names
      install_deps 'haml', :type => Gem

      sass_names.flatten.each do |name|
        sass_file = "public/stylesheets/sass/#{name}.sass"
        css_file  = "public/stylesheets/#{name}.css"
        sass_cmd  = "cd #{self.checkout_path} && sass #{sass_file} #{css_file}"

        @shell.call sass_cmd
      end
    end


    ##
    # Get the deploy server's shell environment.

    def shell_env
      @shell.env
    end


    ##
    # Run the app's start script. Returns false on failure.
    # Post-deploy only.

    def start options=nil
      options ||= {}

      if running?
        return unless options[:force]
        stop
      end

      # Permissions are handled by the script, use: :sudo => false
      run_script :start, :sudo => false
    end


    ##
    # Run the app's start script. Raises an exception on failure.
    # Post-deploy only.

    def start! options=nil
      options ||= {}

      if running?
        return unless options[:force]
        stop!
      end

      # Permissions are handled by the script, use: :sudo => false
      run_script! :start, :sudo => false
    end


    ##
    # Get the app's status: :running or :down.

    def status
      running? ? :running : :down
    end


    ##
    # Run the app's stop script. Returns false on failure.
    # Post-deploy only.

    def stop
      # Permissions are handled by the script, use: :sudo => false
      run_script :stop, :sudo => false
    end


    ##
    # Run the app's stop script. Raises an exception on failure.
    # Post-deploy only.

    def stop!
      # Permissions are handled by the script, use: :sudo => false
      run_script! :stop, :sudo => false
    end


    ##
    # Creates a symlink to the app's checkout path.

    def symlink_current_dir
      @shell.symlink self.checkout_path, self.current_path
    end


    ##
    # Creates a symlink of every script in the scripts_path dir in the
    # app's root directory for easy access.

    def symlink_scripts_to_root
      scripts = @shell.call("ls -1 #{self.scripts_path}").split("\n")

      scripts.each do |name|
        script_file = File.join self.scripts_path, name
        pointer_file = File.join self.root_path, name

        @shell.symlink script_file, pointer_file
      end
    end


    ##
    # Assumes the passed code_dir is the root directory of the checked out
    # codebase and uploads it to the checkout_path.

    def upload_codebase code_dir, scm_info={}
      excludes = scm_info.delete :exclude if scm_info[:exclude]
      excludes = [excludes].flatten.compact
      excludes.map!{|e| "--exclude #{e}"}

      repo = RsyncRepo.new code_dir, :flags => excludes
      repo.checkout_to self.checkout_path, @shell

      @info[:scm] = scm_info
    end


    ##
    # Upload common rake tasks from a local path or the sunshine lib.
    #   app.upload_tasks
    #     #=> upload all tasks
    #   app.upload_tasks 'app', 'common', ...
    #     #=> upload app and common rake files
    #
    # File paths may also be used instead of the file's base name but
    # directory structures will not be followed:
    #   app.upload_tasks 'lib/common/app.rake', 'lib/do_thing.rake'
    #
    # Allows options:
    # :local_path:: str - the path to get rake tasks from
    # :remote_path:: str - the remote absolute path to upload the files to

    def upload_tasks *files
      options     = Hash === files[-1] ? files.delete_at(-1) : {}
      remote_path = options[:remote_path] || "#{self.checkout_path}/lib/tasks"
      local_path  = options[:local_path] || "#{Sunshine::ROOT}/templates/tasks"

      @shell.call "mkdir -p #{remote_path}"

      files.map! do |file|
        if File.basename(file) == file
          File.join(local_path, "#{file}.rake")
        else
          file
        end
      end

      files = Dir.glob("#{Sunshine::ROOT}/templates/tasks/*") if files.empty?

      files.each do |file|
        remote_file = File.join remote_path, File.basename(file)
        @shell.upload file, remote_file
      end
    end


    ##
    # Write an executable bash script to the app's scripts dir
    # on the deploy server, and symlink them to the root dir.

    def write_script name, contents
      script_file = "#{self.scripts_path}/#{name}"

      @shell.make_file script_file, contents,
        :flags => '--chmod=ugo=rwx' unless @shell.file? script_file
    end


    private


    ##
    # Set all the app paths based on the root app path.

    def assign_local_app_attr name, options={}
      @name          = name
      @deploy_name   = options[:deploy_name] || Time.now.to_i

      default_root   = File.join(Sunshine.web_directory, @name)
      @root_path     = options[:root_path] || default_root

      @current_path  = "#{@root_path}/current"
      @deploys_path  = "#{@root_path}/deploys"
      @shared_path   = "#{@root_path}/shared"
      @log_path      = "#{@shared_path}/log"
      @checkout_path = "#{@deploys_path}/#{@deploy_name}"
      @scripts_path  = "#{@checkout_path}/sunshine_scripts"
    end
  end
end

