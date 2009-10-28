module Sunshine

  class DeployServer

    attr_reader :host, :user, :app

    def initialize(user_at_host, app, options={})
      @user, @host = user_at_host.split("@")
      @user ||= options[:user]
      @password = options[:password]
      @app = app
    end

    def connect
      args = [@host, @user, @password].compact
      @ssh_session = Net::SSH.start(*args)
    end

    def connected?
      @ssh_session && !@ssh_session.closed?
    end

    def disconnect
      @ssh_session.close
      @ssh_session = nil
    end

    def make_file!(filepath, content)
      run "test -f #{filepath} && rm #{filepath}"
      run "echo '#{content}' >> #{filepath}"
    end

    def run(string_cmd)
      @ssh_session.exec!(string_cmd)
    end

  end

end
