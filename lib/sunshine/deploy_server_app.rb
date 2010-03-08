module Sunshine

  ##
  # Handles App deployment functionality for a single deploy server.
  #
  # Deploy servers can be assigned any number of roles for classification.
  # :roles:: sym|array - roles assigned (web, db, app, etc...)

  class DeployServerApp < DeployServer


    attr_accessor :app, :roles, :scripts, :info

    def initialize app, host, options={}

      @app = app

      @roles = options[:roles] || []
      @roles = @roles.split(" ") if String === @roles
      @roles = [*@roles].compact.map{|r| r.to_sym }

      @scripts = Hash.new{|h, k| h[k] = []}
      @info    = {:ports => {}}

      super host, options
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
        build_scripts[:restart] << "#{@app.deploy_path}/stop"
        build_scripts[:restart] << "#{@app.deploy_path}/start"
      end

      build_scripts.each do |name, cmds|
        if cmds.empty?
          Sunshine.logger.warn @host, "#{name} script is empty"
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

      make_file "#{@app.checkout_path}/info", deploy_info

      symlink "#{@app.current_path}/info", "#{@app.deploy_path}/info"
    end



    ##
    # Checks out the app's codebase to one or all deploy servers.

    def checkout_codebase
      @info[:scm] = @app.repo.checkout_to @app.checkout_path, self
    end


    ##
    # Returns the most current deploy information.

    def get_deploy_info
      { :deployed_at => Time.now.to_s,
        :deployed_as => call("whoami"),
        :deployed_by => Sunshine.console.user,
        :deploy_name => File.basename(@app.checkout_path),
        :roles       => @roles,
        :path        => @app.deploy_path
      }.merge @info
    end


    ##
    # Decrypt a file using gpg. Allows options:
    # :output:: str - the path the output file should go to
    # :passphrase:: str - the passphrase gpg should use

    def gpg_decrypt gpg_file, options={}
      output_file     = options[:output] || gpg_file.gsub(/\.gpg$/, '')

      passphrase      = options[:passphrase]
      passphrase_file = "#{@app.deploy_path}/tmp/gpg_passphrase"

      gpg_cmd = "gpg --batch --no-tty --yes --output #{output_file} "+
        "--passphrase-file #{passphrase_file} --decrypt #{gpg_file}"

      call "mkdir -p #{File.dirname(passphrase_file)}"

      make_file passphrase_file, passphrase

      call "cd #{@app.checkout_path} && #{gpg_cmd}"
      call "rm -f #{passphrase_file}"
    end


    ##
    # Install dependencies previously defined in Sunshine::Dependencies

    def install_deps(*deps)
      deps.each do |d|
        d = Sunshine::Dependencies[d] if String === d
        d.install! :call => self
      end
    end


    ##
    # Install gem dependencies defined by the app's checked-in
    # bundler or geminstaller config.

    def install_gems
      run_bundler if file?("#{@app.checkout_path}/Gemfile")

      run_geminstaller if file?("#{@app.checkout_path}/config/geminstaller.yml")
    end


    ##
    # Creates the required application directories.

    def make_app_directories
      call "mkdir -p #{@app.directories.join(" ")}"
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
  #{@app.deploy_path}/env #{@app.deploy_path}/#{name} --no-env
fi
      STR
    end


    ##
    # Creates the one-off env script that will be used by other scripts
    # to correctly set their env variables.

    def make_env_bash_script
      env_str = @env.map{|e| e.join("=")}.join(" ")
      "#!/bin/bash\nenv #{env_str} \"$@\""
    end


    ##
    # Run a rake task the deploy server.

    def rake command
      install_deps 'rake'
      call "cd #{@app.checkout_path} && rake #{command}"
    end


    ##
    # Adds the app to the deploy server's deployed-apps list

    def register_as_deployed
      AddCommand.exec @app.deploy_path, 'servers' => [self]
    end


    ##
    # Removes old deploys from the checkout_dir
    # based on Sunshine's max_deploy_versions.

    def remove_old_deploys
      deploys = call("ls -1 #{@app.deploys_dir}").split("\n")

      return unless deploys.length > Sunshine.max_deploy_versions

      lim = Sunshine.max_deploy_versions + 1

      rm_deploys = deploys[0..-lim]
      rm_deploys.map!{|d| "#{@app.deploys_dir}/#{d}"}

      call("rm -rf #{rm_deploys.join(" ")}")
    end


    ##
    # Run the app's restart script

    def restart
      call "#{@app.deploy_path}/restart"
    end



    ##
    # Symlink current directory to previous checkout and remove
    # the current deploy directory.

    def revert!
      call "rm -rf #{@app.checkout_path}"

      last_deploy = call("ls -rc1 #{@app.deploys_dir}").split("\n").last

      if last_deploy && !last_deploy.empty?
        symlink "#{@app.deploys_dir}/#{last_deploy}", @app.current_path

        started = StartCommand.exec [@app.name],
          'servers' => [self], 'force' => true

        Sunshine.logger.info @host, "Reverted to #{last_deploy}"

        Sunshine.logger.error @host, "Failed starting #{@name}" if !started

      else
        @app.crontab.delete! self

        Sunshine.logger.info @host, "No previous deploy to revert to."
      end
    end


    ##
    # Runs bundler. Installs the bundler gem if missing.

    def run_bundler
      install_deps 'bundler'
      call "cd #{@app.checkout_path} && gem bundle"
    end


    ##
    # Runs geminstaller. :(
    # Deprecated: use bundler

    def run_geminstaller
      install_deps 'geminstaller'
      call "cd #{@app.checkout_path} && geminstaller -e"
    end


    ##
    # Check if the app pids are present.

    def running?
      call "#{@app.deploy_path}/status"
    end


    ##
    # Run a sass task on any or all deploy servers.

    def sass *sass_names
      install_deps 'haml'

      sass_names.flatten.each do |name|
        sass_file = "public/stylesheets/sass/#{name}.sass"
        css_file  = "public/stylesheets/#{name}.css"
        sass_cmd  = "cd #{@app.checkout_path} && sass #{sass_file} #{css_file}"

        call sass_cmd
      end
    end


    ##
    # Get the deploy server's shell environment.

    def shell_env
      @env
    end


    ##
    # Run the app's start script

    def start force=false
      stop if running? && force
      call "#{@app.deploy_path}/start"
    end


    ##
    # Run the app's stop script

    def stop
      call "#{@app.deploy_path}/stop"
    end


    ##
    # Creates a symlink to the app's checkout path.

    def symlink_current_dir
      symlink(@app.checkout_path, @app.current_path)
    end


    ##
    # Upload common rake tasks from the sunshine lib.
    #   app.upload_tasks
    #     #=> upload all tasks
    #   app.upload_tasks 'tpkg', 'common', ...
    #     #=> upload tpkg and common rake files
    #
    # Allows options:
    # :remote_path:: str - the remote absolute path to upload the files to

    def upload_tasks *files
      options   = Hash === files[-1] ? files.delete_at(-1) : {}
      path      = options[:remote_path] || "#{@app.checkout_path}/lib/tasks"

      call "mkdir -p #{path}"

      files.map!{|f| "templates/tasks/#{f}.rake"}
      files = Dir.glob("templates/tasks/*") if files.empty?

      files.each do |f|
        remote = File.join path, File.basename(f)
        upload f, remote
      end
    end


    ##
    # Write an executable bash script to the app's checkout dir
    # on the deploy server, and symlink them to the current dir.

    def write_script name, contents

      make_file "#{@app.checkout_path}/#{name}", contents,
          :flags => '--chmod=ugo=rwx'

      symlink "#{@app.current_path}/#{name}",
        "#{@app.deploy_path}/#{name}"
    end
  end
end

