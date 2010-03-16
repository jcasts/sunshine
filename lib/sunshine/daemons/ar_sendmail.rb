module Sunshine

  ##
  # Simple daemon wrapper for ar_sendmail setup and control.
  # By default, uses server apps with the :mail role.

  class ARSendmail < Daemon

    def initialize app, options={}
      options[:server_apps] ||= app.find(:role => :mail)

      super app, options

      @dep_name = options[:dep_name] || 'ar_mailer'
    end


    def start_cmd
      "cd #{@app.current_path} && #{@bin} -p #{@pid} -d"
    end


    def stop_cmd
      "test -f #{@pid} && kill `cat #{@pid}` || "+
        "echo 'No #{@name} process to stop for #{@app.name}'; rm -f #{@pid};"
    end
  end
end
