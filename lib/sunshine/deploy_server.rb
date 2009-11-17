module Sunshine

  class DeployServer

    class ConnectionError < FatalDeployError; end

    attr_reader :host, :user, :app

    MAX_TRIES = 3

    def initialize(user_at_host, app, options={})
      @user, @host = user_at_host.split("@")
      @user ||= options.delete(:user)
      @options = options
      @app = app
      @ssh_session = nil
    end

    def connect
      return if connected?
      sunshine_info "Connecting..."
      tries = 0
        begin
          @ssh_session = Net::SSH.start(@host, @user, @options)
        rescue Net::SSH::AuthenticationFailed => e
          raise ConnectionError, "Failed to connect to #{@host}" unless tries < MAX_TRIES
          tries = tries.next
          sunshine_info "#{e.class}: #{e.message}"
          Sunshine.logger.info :ssh, "User '#{@user}' can't log into #{@host}. Try entering a password (#{tries}/#{MAX_TRIES}):"
          begin
            system "stty -echo"
            @options[:password] = gets.chomp
          ensure
            system "stty echo"
          end
          retry
        end
    end

    def connected?
      !@ssh_session.nil? && !@ssh_session.closed?
    end

    def disconnect
      return unless connected?
      sunshine_info "Disconnecting..."
      @ssh_session.close
      @ssh_session = nil
    end

    def upload(from_path, to_path, options={}, &block)
      raise Errno::ENOENT, "No such file or directory - #{from_path}" unless File.exists?(from_path)
      sunshine_info "Uploading #{from_path} -> #{to_path}"
      @ssh_session.scp.upload!(from_path, to_path, options, &block)
    end

    def download(from_path, to_path, options={}, &block)
      sunshine_info "Downloading #{from_path} -> #{to_path}"
      @ssh_session.scp.download!(from_path, to_path, options, &block)
    end

    def make_file(filepath, content, options={})
      FileUtils.mkdir_p "tmp"
      temp_filepath = "tmp/#{Time.now.to_i}_#{File.basename(filepath)}"
      File.open(temp_filepath, "w+"){|f| f.write(content)}
      upload(temp_filepath, filepath, options)
      File.delete(temp_filepath)
      Dir.delete("tmp") if Dir.glob("tmp/*").empty?
    end

    def symlink(target, symlink_name)
      run "ln -sfT #{target} #{symlink_name}"
    end

    def run(string_cmd, &block)
      sunshine_info "Running: #{string_cmd}"
      stdout = ""
      stderr = ""
      output = ""
      last_stream = nil
      @ssh_session.exec!(string_cmd) do |channel, stream, data|
        stdout << data if stream == :stdout
        stderr << data if stream == :stderr
        output << data
        last_stream = stream
        yield(stream, data) if block_given?
      end
      Sunshine.logger.log(@host, output, :type => (last_stream == :stdout ? :debug : :error))
      raise SSHCmdError.new(stderr, self) if last_stream == :stderr && !stderr.empty?
      stdout
    end

    def os_name
      @os_name ||= run("uname -s").strip.downcase
    end


    private

    def sunshine_info(message)
      Sunshine.logger.info @host, message, :indent => 1, :nl => 0
    end

  end

end
