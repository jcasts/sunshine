module Sunshine

  class DeployServer

    class ConnectionError < FatalDeployError; end

    include Open4

    SUDO_PROMPT = /^Password:/

    attr_reader :host, :user
    attr_accessor :roles, :env


    def initialize host, options={}
      @host = host
      @user = options[:user]
      @roles = options[:roles].to_a.map{|r| r.to_sym }
      @env = options[:env] || {}
      @password = options[:password]

      @ssh_flags = [
        "-o ControlMaster=auto",
        "-o ControlPath=~/.ssh/sunshine-%r@%h:%p"
      ]
      @ssh_flags << "-l #{@user}" if @user
      @ssh_flags.concat options[:ssh_flags].to_a

      @pid, @inn, @out, @err = nil
    end

    ##
    # Checks for equality
    def ==(deploy_server)
      @host == deploy_server.host && @user == deploy_server.user
    end

    ##
    # Checks for equality
    def ==(deploy_server)
      @host == deploy_server.host && @user == deploy_server.user
    end

    ##
    # Connect to host via SSH. Queries for password on fail
    def connect
      return @pid if connected?
      command = "echo 'ready'; for (( ; ; )); do sleep 100; done"
      cmd = ["ssh", @ssh_flags, @host, command].flatten
      @pid, @inn, @out, @err = popen4(*cmd)
      @inn.sync = true

      data = ""
      ready = false
      until ready || @out.eof? do
        data << @out.readpartial(1024)
        ready = data == "ready\n"
      end

      unless ready
        disconnect
        raise ConnectionError, "Can't connect to #{@host}"
      end

      @pid
    end

    ##
    # Prompt the user for a password
    def prompt_for_password
      @password = Sunshine.console.ask("#{@host} Password:") do |q|
        q.echo = "•"
      end
    end

    ##
    # Check if SSH session is open
    def connected?
      Process.kill(0, @pid) && @pid rescue false
    end

    ##
    # Disconnect from host
    def disconnect
      return unless connected?

      begin
        Process.kill("HUP", @pid)
        Process.wait
      rescue
      end

      @inn.close rescue nil
      @out.close rescue nil
      @err.close rescue nil
      @pid = nil
    end

    ##
    # Uploads a file via rsync
    def upload(from_path, to_path, sudo=false)
      Sunshine.logger.info @host, "Uploading #{from_path} -> #{to_path}" do
        cmd = build_rsync_cmd from_path, "#{@host}:#{to_path}", sudo
        run_cmd(cmd)
      end
    end

    ##
    # Download a file via rsync
    def download(from_path, to_path, sudo=false)
      Sunshine.logger.info @host, "Downloading #{from_path} -> #{to_path}" do
        cmd = build_rsync_cmd "#{@host}:#{from_path}", to_path, sudo
        run_cmd(cmd)
      end
    end

    ##
    # Checks if the given file exists
    def file?(filepath)
      run("test -f #{filepath}") && true rescue false
    end

    ##
    # Create a file remotely
    def make_file(filepath, content, sudo=false)
      FileUtils.mkdir_p "tmp"
      temp_filepath =
        "tmp/#{File.basename(filepath)}_#{Time.now.to_i}#{rand(10000)}"
      File.open(temp_filepath, "w+"){|f| f.write(content)}

      self.upload(temp_filepath, filepath, sudo)

      File.delete(temp_filepath)
      Dir.delete("tmp") if Dir.glob("tmp/*").empty?
    end

    ##
    # Force symlinking a remote directory
    def symlink(target, symlink_name)
      run "ln -sfT #{target} #{symlink_name}"
    end

    ##
    # Runs a command via SSH. Optional block is passed the
    # stream(stderr, stdout) and string data
    def run(command_str, sudo=false)
      command = build_ssh_cmd(command_str, sudo)
      cmd = ["ssh", @ssh_flags, @host, command].flatten

      Sunshine.logger.info @host, "Running: #{command_str}" do
        run_cmd(*cmd)
      end
    end


    alias call run

    ##
    # Get the name of the remote OS
    def os_name
      @os_name ||= run("uname -s").strip.downcase
    end


    private

    def build_rsync_cmd(from_path, to_path, sudo=false)
      ssh  = ["-e", "\"ssh #{@ssh_flags.join(' ')}\""] if @ssh_flags
      sudo = sudo ? "--rsync-path='sudo rsync'" : nil

      cmd  = ["rsync", "-azP", sudo, ssh, from_path, to_path]
      cmd.flatten.compact.join(" ")
    end

    def build_ssh_cmd(string, sudo=false)
      string = string.gsub(/'/){|s| "'\\''"}
      string = "'#{string}'"
      cmd = ["sh", "-c", string]
      cmd.unshift "sudo" if sudo
      if @env && !@env.empty?
        env_vars = @env.to_a.map{|e| e.join("=")}
        cmd = ["env", env_vars, cmd]
      end
      cmd.flatten
    end

    def run_cmd(*cmd)
      result = Hash.new{|h,k| h[k] = []}

      pid, inn, out, err = popen4(*cmd)

      inn.sync   = true
      streams    = [out, err]

      # Handle process termination ourselves
      status = nil
      Thread.start do
        status = Process.waitpid2(pid).last
      end

      until streams.empty? do
        # don't busy loop
        selected, = select streams, nil, nil, 0.1

        next if selected.nil? or selected.empty?

        selected.each do |stream|
          if stream.eof? then
            streams.delete stream if status # we've quit, so no more writing
            next
          end

          data = stream.readpartial(1024)

          Sunshine.logger.debug ">>", data if stream == out
          Sunshine.logger.error ">>", data if stream == err

          if stream == err && data =~ SUDO_PROMPT then
            inn.puts(@password || prompt_for_password)
            data << "\n"
            Sunshine.console << "\n"
          end

          result[stream] << data
        end
      end

      unless status.success? then
        msg = "Execution failed with status #{status.exitstatus}: #{cmd.join ' '}"
        raise CmdError.new(self, msg)
      end

      result[out].join.chomp

    ensure
      inn.close rescue nil
      out.close rescue nil
      err.close rescue nil
    end

  end

end
