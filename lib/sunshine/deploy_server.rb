module Sunshine

  class DeployServer

    class ConnectionError < FatalDeployError; end

    attr_reader :host, :user
    attr_accessor :roles

    MAX_CONNECT_TRIES = 3

    def initialize(user_at_host, options={})
      @user, @host = user_at_host.split("@")
      @user ||= options.delete(:user)
      @roles = options.delete(:roles).to_a
      @options = options
      @ssh_session = nil
    end

    ##
    # Connect to host via SSH. Queries for password on fail
    def connect
      return if connected?
      Sunshine.logger.info @host, "Connecting..."

      tries = 0
      begin

        @ssh_session = Net::SSH.start(@host, @user, @options)

      rescue Net::SSH::AuthenticationFailed => e

        raise ConnectionError, "Failed to connect to #{@host}" unless tries < MAX_CONNECT_TRIES
        tries = tries.next

        Sunshine.logger.info @host, "#{e.class}: #{e.message}"

        Sunshine.logger.info :ssh, "User '#{@user}' can't log into #{@host}. Try entering a password (#{tries}/#{MAX_CONNECT_TRIES}):"

        @options[:password] = self.query_for_password
        retry

      end
    end

    ##
    # Query the user for a password
    def query_for_password
      password = nil
      begin
        system "stty -echo"
        password = gets.chomp
      ensure
        system "stty echo"
      end
      password
    end

    ##
    # Check if SSH session is open
    def connected?
      !@ssh_session.nil? && !@ssh_session.closed?
    end

    ##
    # Disconnect from host
    def disconnect
      return unless connected?
      Sunshine.logger.info @host, "Disconnecting..."
      @ssh_session.close
      @ssh_session = nil
    end

    ##
    # Uploads a file via SCP
    def upload(from_path, to_path, options={}, &block)
      raise Errno::ENOENT, "No such file or directory - #{from_path}" unless File.exists?(from_path)
      Sunshine.logger.info @host, "Uploading #{from_path} -> #{to_path}"
      @ssh_session.scp.upload!(from_path, to_path, options, &block)
    end

    ##
    # Download a file via SCP
    def download(from_path, to_path, options={}, &block)
      Sunshine.logger.info @host, "Downloading #{from_path} -> #{to_path}"
      @ssh_session.scp.download!(from_path, to_path, options, &block)
    end

    ##
    # Create a file remotely
    def make_file(filepath, content, options={})
      FileUtils.mkdir_p "tmp"
      temp_filepath = "tmp/#{File.basename(filepath)}_#{Time.now.to_i}#{rand(10000)}"
      File.open(temp_filepath, "w+"){|f| f.write(content)}

      self.upload(temp_filepath, filepath, options)

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
    def run(string_cmd, &block)
      stdout = ""
      stderr = ""
      last_stream = nil
      Sunshine.logger.info @host, "Running: #{string_cmd}" do
        @ssh_session.exec!(string_cmd) do |channel, stream, data|
          stdout << data if stream == :stdout
          stderr << data if stream == :stderr
          last_stream = stream unless data.chomp.empty?
          Sunshine.logger.log(">>", data, :type => (last_stream == :stdout ? :debug : :error))
          yield(stream, data) if block_given?
        end
      end
      raise SSHCmdError.new(stderr, self) if last_stream == :stderr && !stderr.empty?
      stdout
    end

    def os_name
      @os_name ||= run("uname -s").strip.downcase
    end

  end

end
