module Sunshine

  class DeployServer

    class SSHCmdError < CmdError

      attr_reader :deploy_server

      def initialize(message=nil, deploy_server=nil)
        @deploy_server = deploy_server
        super(message)
      end

    end

    attr_reader :host, :user, :app

    def initialize(user_at_host, app, options={})
      @user, @host = user_at_host.split("@")
      @user ||= options[:user]
      @password = options[:password]
      @app = app
      @ssh_session = nil
    end

    def connect
      return if connected?
      sunshine_info "Connecting..."
      args = [@host, @user, @password].compact
      @ssh_session = Net::SSH.start(*args)
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

    def make_file!(filepath, content)
      FileUtils.mkdir_p "tmp"
      temp_filepath = "tmp/#{Time.now.to_i}_#{File.basename(filepath)}"
      File.open(temp_filepath, "w+"){|f| f.write(content)}
      upload(temp_filepath, filepath)
      File.delete(temp_filepath)
      Dir.delete("tmp") if Dir.glob("tmp/*").empty?
    end

    def symlink(target, symlink_name)
      run "ln -sfT #{target} #{symlink_name}"
    end

    def run(string_cmd, &block)
      sunshine_info "Running: #{string_cmd}"
      stdout = ""
      @ssh_session.exec!(string_cmd) do |channel, stream, data|
        stdout << data if stream == :stdout
        yield(stream, data) if block_given?
        raise SSHCmdError.new(data, self) if stream == :stderr
      end
      stdout
    end

    def os_name
      @os_name ||= run("uname -s").strip.downcase
    end


    private

    def sunshine_info(message)
      Sunshine.info @host, message, :indent => 1, :nl => 0
    end

  end

end
