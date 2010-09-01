module Sunshine

  ##
  # Simple daemon wrapper for ar_sendmail setup and control.
  # By default, uses server apps with the :mail role.

  class ARSendmail < Daemon

    def initialize app, options={}
      options[:role] ||= :mail

      super app, options

      @dep_name = options[:dep_name] || 'ar_mailer'
    end


    def start_cmd
      "cd #{@app.current_path} && #{@bin} -p #{@pid} -d"
    end
  end
end
