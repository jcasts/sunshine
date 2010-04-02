module Sunshine

  ##
  # Simple daemon wrapper for delayed_job daemon setup and control.
  # By default, uses server apps with the :dj role. Supports
  # the :processes option.
  #
  # Note: The pid location is fixed at [current_path]/tmp/pids/delayed_job.pid"

  class DelayedJob < Daemon

    def initialize app, options={}
      options[:role] ||= :dj

      super app, options

      @pid = "#{@app.current_path}/tmp/pids/delayed_job.pid"

      @dep_name = options[:dep_name] || "daemons"
    end


    def start_cmd
      "cd #{@app.current_path} && script/delayed_job -n #{@processes} start"
    end


    def stop_cmd
      "cd #{@app.current_path} && script/delayed_job stop"
    end
  end
end
