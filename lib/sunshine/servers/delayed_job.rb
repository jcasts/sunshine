module Sunshine

  ##
  # Simple server wrapper for ar_sendmail setup and control.

  class DelayedJob < Server

    def initialize app, options={}
      super

      @deploy_servers = options[:deploy_servers] ||
        @app.deploy_servers.find(:role => :dj)
    end


    def start_cmd
      "cd #{@app.current_path} && script/delayed_job start"
    end


    def stop_cmd
      "cd #{@app.current_path} && script/delayed_job stop"
    end
  end
end
