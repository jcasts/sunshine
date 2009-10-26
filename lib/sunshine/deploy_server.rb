module Sunshine

  class DeployServer

    attr_reader :url, :user, :app

    def initialize(user_at_url, app)
      @user, @url = user_at_url.split("@")
      @app = app
    end

    def run(string_cmd)
      true
    end

  end

end
