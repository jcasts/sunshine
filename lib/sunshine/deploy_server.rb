require 'tmpdir'

module Sunshine

  ##
  # Keeps an SSH connection open to a server the app will be deployed to.
  # Deploy servers use the ssh command and support any ssh feature.
  # By default, deploy servers use the ControlMaster feature to share
  # socket connections, with the ControlPath = ~/.ssh/sunshine-%r%h:%p
  #
  # Deploy servers can be assigned any number of roles for classification.
  #
  # Setting session-persistant environment variables is supported by
  # accessing the @env attribute.

  class DeployServer < Console

    class ConnectionError < FatalDeployError; end

    TMP_DIR = File.join Dir.tmpdir, "sunshine_#{$$}"

    attr_reader :host, :user
    attr_accessor :roles, :env, :ssh_flags


    ##
    # Deploy servers essentially need a user and a host. Typical instantiation
    # is done through either of these methods:
    #   DeployServer.new "user@host"
    #   DeployServer.new "host", :user => "user"
    #
    # The constructor also supports the following options:
    # :roles:: sym|array - roles assigned (web, db, app, etc...)
    # :env:: hash - hash of environment variables to set for the ssh session
    # :password:: string - password for ssh login; if missing the deploy server
    #                      will attempt to prompt the user for a password.

    def initialize host, options={}
      super $stdout

      @host, @user = host.split("@").reverse

      @user     ||= options[:user]
      @roles    = [*options[:roles]].map{|r| r.to_sym }
      @env      = options[:env] || {}
      @password = options[:password]

      @ssh_flags = [
        "-o ControlMaster=auto",
        "-o ControlPath=~/.ssh/sunshine-%r@%h:%p"
      ]
      @ssh_flags.concat ["-l", @user] if @user
      @ssh_flags.concat options[:ssh_flags].to_a

      @pid, @inn, @out, @err = nil
    end


    ##
    # Checks for equality

    def == deploy_server
      @host == deploy_server.host && @user == deploy_server.user
    end


    ##
    # Connect to host via SSH and return process pid

    def connect
      return @pid if connected?

      cmd = ssh_cmd "echo ready; for (( ; ; )); do sleep 100; done"

      @pid, @inn, @out, @err = popen4(*cmd)
      @inn.sync = true

      data  = ""
      ready = @out.readline == "ready\n"

      unless ready
        disconnect
        raise ConnectionError, "Can't connect to #{@user}@#{@host}"
      end

      @inn.close
      @pid
    end


    ##
    # Check if SSH session is open and returns process pid

    def connected?
      Process.kill(0, @pid) && @pid rescue false
    end


    ##
    # Disconnect from host

    def disconnect
      return unless connected?

      begin
        Process.kill "HUP", @pid
        Process.wait
      rescue
      end

      @inn.close rescue nil
      @out.close rescue nil
      @err.close rescue nil
      @pid = nil
    end


    ##
    # Download a file via rsync

    def download from_path, to_path, sudo=false, &block
      from_path = "#{@host}:#{from_path}"
      Sunshine.logger.info @host, "Downloading #{from_path} -> #{to_path}" do
        execute rsync_cmd(from_path, to_path, sudo), &block
      end
    end


    ##
    # Checks if the given file exists

    def file? filepath
      run("test -f #{filepath}") && true rescue false
    end


    ##
    # Create a file remotely

    def make_file filepath, content, sudo=false
      FileUtils.mkdir_p TMP_DIR

      temp_filepath =
        "#{TMP_DIR}/#{File.basename(filepath)}_#{Time.now.to_i}#{rand(10000)}"

      File.open(temp_filepath, "w+"){|f| f.write(content)}

      self.upload(temp_filepath, filepath, sudo)

      File.delete(temp_filepath)
      FileUtils.rm_rf TMP_DIR if Dir.glob("#{TMP_DIR}/*").empty?
    end


    ##
    # Get the name of the OS

    def os_name
      @os_name ||= run("uname -s").strip.downcase
    end


    ##
    # Runs a command via SSH. Optional block is passed the
    # stream(stderr, stdout) and string data

    def run command_str, sudo=false, &block
      Sunshine.logger.info @host, "Running: #{command_str}" do
        execute ssh_cmd(command_str, sudo), &block
      end
    end

    alias call run


    ##
    # Force symlinking a remote directory

    def symlink target, symlink_name
      run "ln -sfT #{target} #{symlink_name}" rescue false
    end


    ##
    # Uploads a file via rsync

    def upload from_path, to_path, sudo=false, &block
      to_path = "#{@host}:#{to_path}"
      Sunshine.logger.info @host, "Uploading #{from_path} -> #{to_path}" do
        execute rsync_cmd(from_path, to_path, sudo), &block
      end
    end


    private

    def rsync_cmd from_path, to_path, sudo=false
      ssh  = ["-e", "\"ssh #{@ssh_flags.join(' ')}\""] if @ssh_flags
      sudo = sudo ? "--rsync-path='sudo rsync'" : nil

      cmd  = ["rsync", "-azP", sudo, ssh, from_path, to_path]
      cmd.flatten.compact.join(" ")
    end


    def ssh_cmd string, sudo=false
      string = string.gsub(/'/){|s| "'\\''"}
      string = "'#{string}'"

      cmd = ["sh", "-c", string]
      cmd.unshift "sudo" if sudo

      if @env && !@env.empty?
        env_vars = @env.to_a.map{|e| e.join("=")}
        cmd      = ["env", env_vars, cmd]
      end

      ["ssh", @ssh_flags, @host, cmd].flatten.compact
    end
  end
end
