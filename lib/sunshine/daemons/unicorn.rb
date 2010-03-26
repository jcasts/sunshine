module Sunshine

  ##
  # Simple server wrapper for Unicorn setup and control.

  class Unicorn < Server

    def initialize app, options={}
      super

      @timeout = options[:timeout] || 3.0

      @supports_rack = true
    end


    def start_cmd
      "cd #{@app.current_path} && #{@bin} -D -E #{@app.deploy_env} "+
        "-p #{@port} -c #{self.config_file_path};"
    end
  end
end
