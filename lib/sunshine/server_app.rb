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
    # Define an attribue that will get a value from app, or locally if
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


    app_attr :name, :deploy_name
    app_attr :root_path, :checkout_path, :current_path
    app_attr :deploys_path, :log_path, :shared_path

    attr_accessor :app, :roles, :scripts, :info, :shell, :crontab, :health
    attr_writer :pkg_manager

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

      write_script "env", make_env_bash_script

      build_scripts = @scripts.dup

      if build_scripts[:restart].empty? &&
        !build_scripts[:start].empty? && !build_scripts[:stop].empty?
        build_scripts[:restart] << "#{self.root_path}/stop"
        build_scripts[:restart] << "#{self.root_path}/start"
      end

      if build_scripts[:status].empty?
        build_scripts[:status] << "echo 'No daemons for #{self.name}'; exit 1;"
      end

      build_scripts.each do |name, cmds|
        if cmds.empty?
          Sunshine.logger.warn @shell.host, "#{name} script is empty"
        end

        bash = make_bash_script name, cmds

        write_script name, bash
      end
    end


    ##
    # Creates a yaml file with deploy information. To add custom information
    # to the info file, use the app's info hash attribute:
    #   app.info[:key] = "some value"

    def build_deploy_info_file

      deploy_info = get_deploy_info.to_yaml

      @shell.make_file "#{self.checkout_path}/info", deploy_info

      @shell.symlink "#{self.current_path}/info", "#{self.root_path}/info"
    end



    ##
    # Checks out the app's codebase to the checkout path.

    def checkout_repo repo
      @info[:scm] = repo.checkout_to self.checkout_path, @shell
    end


    ##
    # Get post-mortum information about the app's deploy, from the
    # generated deploy info file.
    # Post-deploy only.

    def deploy_details reload=false
      return @deploy_details if @deploy_details && !reload
      @deploy_details =
        YAML.load @shell.call("cat #{self.current_path}/info") rescue nil
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
      [root_path, deploys_path, shared_path, log_path, checkout_path]
    end


    ##
    # Returns information about the deploy at hand.

    def get_deploy_info
      { :deployed_at => Time.now.to_s,
        :deployed_as => @shell.call("whoami"),
        :deployed_by => Sunshine.shell.user,
        :deploy_name => File.basename(self.checkout_path),
        :roles       => @roles,
        :path        => self.root_path
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

    def has_roles? *roles
      return true if @roles.include? :all

      roles.each do |role|
        return false unless @roles.include? role
      end

      true
    end


    %w{gem yum apt tpkg}.each do |dep_type|
      self.class_eval <<-STR, __FILE__, __LINE__ + 1
        ##
        # Install one or more #{dep_type} packages.
        # See Settler::#{dep_type.capitalize}#new for supported options.

        def #{dep_type}_install(*names)
          options = Hash === names.last ? names.delete_at(-1) : Hash.new

          names.each do |name|
            dep = Settler::#{dep_type.capitalize}.new(name, options)
            dep.install! :call => @shell
          end
        end
      STR
    end


    ##
    # Install dependencies previously defined in Sunshine::Dependencies.

    def install_deps(*deps)
      options = {:call => @shell, :prefer => pkg_manager}
      options.merge! deps.delete_at(-1) if Hash === deps.last

      args = deps << options
      Sunshine::Dependencies.install(*args)
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
        (@shell.call("yum -v") && Settler::Yum) rescue Settler::Apt
    end


    ##
    # Run a rake task the deploy server.

    def rake command
      install_deps 'rake', :type => Settler::Gem
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
      deploys = @shell.call("ls -1 #{self.deploys_path}").split("\n")

      return unless deploys.length > Sunshine.max_deploy_versions

      lim = Sunshine.max_deploy_versions + 1

      rm_deploys = deploys[0..-lim]
      rm_deploys.map!{|d| "#{self.deploys_path}/#{d}"}

      @shell.call("rm -rf #{rm_deploys.join(" ")}")
    end


    ##
    # Run the app's restart script
    # Post-deploy only.

    def restart
      @shell.call "#{self.root_path}/restart"
    end


    ##
    # Symlink current directory to previous checkout and remove
    # the current deploy directory.

    def revert!
      @shell.call "rm -rf #{self.checkout_path}"

      last_deploy = @shell.call("ls -rc1 #{self.deploys_path}").split("\n").last

      if last_deploy && !last_deploy.empty?
        @shell.symlink "#{self.deploys_path}/#{last_deploy}", self.current_path

        started = start(:force => true) rescue false

        Sunshine.logger.info @shell.host, "Reverted to #{last_deploy}"

        Sunshine.logger.error @shell.host, "Failed #{@name} startup" if !started

      else
        @crontab.delete!

        Sunshine.logger.info @shell.host, "No previous deploy to revert to."
      end
    end


    ##
    # Runs bundler. Installs the bundler gem if missing.

    def run_bundler
      install_deps 'bundler', :type => Settler::Gem
      @shell.call "cd #{self.checkout_path} && gem bundle"
    end


    ##
    # Runs geminstaller. :(
    # Deprecated: use bundler

    def run_geminstaller
      install_deps 'geminstaller', :type => Settler::Gem
      @shell.call "cd #{self.checkout_path} && geminstaller -e"
    end


    ##
    # Check if the app pids are present.
    # Post-deploy only.

    def running?
      @shell.call "#{self.root_path}/status" rescue false
    end


    ##
    # Run a sass task on any or all deploy servers.

    def sass *sass_names
      install_deps 'haml', :type => Settler::Gem

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
    # Run the app's start script.
    # Post-deploy only.

    def start options=nil
      options ||= {}

      if running?
        return unless options[:force]
        stop
      end

      @shell.call "#{self.root_path}/start"
    end


    ##
    # Run the app's stop script.
    # Post-deploy only.

    def stop
      @shell.call "#{self.root_path}/stop"
    end


    ##
    # Creates a symlink to the app's checkout path.

    def symlink_current_dir
      @shell.symlink(self.checkout_path, self.current_path)
    end


    ##
    # Upload common rake tasks from a local path or the sunshine lib.
    #   app.upload_tasks
    #     #=> upload all tasks
    #   app.upload_tasks 'tpkg', 'common', ...
    #     #=> upload tpkg and common rake files
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

      files = Dir.glob("templates/tasks/*") if files.empty?

      files.each do |file|
        remote_file = File.join remote_path, File.basename(file)
        @shell.upload file, remote_file
      end
    end


    ##
    # Write an executable bash script to the app's checkout dir
    # on the deploy server, and symlink them to the current dir.

    def write_script name, contents

      @shell.make_file "#{self.checkout_path}/#{name}", contents,
          :flags => '--chmod=ugo=rwx'

      @shell.symlink "#{self.current_path}/#{name}",
        "#{self.root_path}/#{name}"
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
    end
  end
end

