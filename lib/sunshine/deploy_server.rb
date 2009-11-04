module Sunshine

  class DeployServer

    class SSHCmdError < CmdError; end

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
      args = [@host, @user, @password].compact
      @ssh_session = Net::SSH.start(*args)
    end

    def connected?
      !@ssh_session.nil? && !@ssh_session.closed?
    end

    def disconnect
      return unless connected?
      @ssh_session.close
      @ssh_session = nil
    end

    def upload(from_path, to_path, options={}, &block)
      raise Errno::ENOENT, "No such file or directory - #{from_path}" unless File.exists?(from_path)
      @ssh_session.scp.upload!(from_path, to_path, options, &block)
    end

    def download(from_path, to_path, options={}, &block)
      @ssh_session.scp.download!(from_path, to_path, options, &block)
    end

    def make_file!(filepath, content)
      run "test -f #{filepath} && rm #{filepath}"
      run "echo '#{content}' >> #{filepath}"
    end

    def run(string_cmd, &block)
      stdout = ""
      @ssh_session.exec!(string_cmd) do |channel, stream, data|
        stdout << data if stream == :stdout
        yield(stream, data) if block_given?
        raise(SSHCmdError, "#{@user}@#{host}: #{data}") if stream == :stderr
      end
      stdout
    end

    def os_name
      @os_name ||= run("uname -s").strip
    end

  end

end
