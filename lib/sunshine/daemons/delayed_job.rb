module Sunshine

  ##
  # Simple daemon wrapper for delayed_job daemon setup and control.
  # By default, uses deploy servers with the :dj role. Supports
  # the :processes option.

  class DelayedJob < Daemon

    def initialize app, options={}
      options[:deploy_servers] ||= app.deploy_servers.find(:role => :dj)

      super app, options

      @pid = "#{@app.current_path}/tmp/pids/delayed_job.pid"

      @dep_name = options[:dep_name] || "daemons-gem"
    end


    def start_cmd
      "cd #{@app.current_path} && script/delayed_job -n #{@processes} start"
    end


    def stop_cmd
      "cd #{@app.current_path} && script/delayed_job stop"
    end
  end
end
