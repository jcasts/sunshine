module Sunshine

  ##
  # Simple server wrapper for ar_sendmail setup and control.

  class ARSendmail < Server

    def initialize app, options={}
      super

      @dep_name = options[:dep_name] || 'ar_mailer'

      @deploy_servers = options[:deploy_servers] ||
        @app.deploy_servers.find(:role => :mail)
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
