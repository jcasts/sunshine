module Sunshine

  ##
  # Simple server wrapper for delayed_job daemon setup and control.
  # By default, uses deploy servers with the :dj role. Supports
  # the :processes option.

  class DelayedJob < Server

    def initialize app, options={}
      super

      @port = nil

      @pid = "#{@app.current_path}/tmp/pids/delayed_job.pid"

      @dep_name = options[:dep_name] || "daemons-gem"

      @deploy_servers = options[:deploy_servers] ||
        @app.deploy_servers.find(:role => :dj)
    end


    def start_cmd
      "cd #{@app.current_path} && script/delayed_job -n #{@processes} start"
    end


    def stop_cmd
      "cd #{@app.current_path} && script/delayed_job stop"
    end
  end
end
