module Sunshine

  ##
  # Simple server wrapper for Unicorn setup and control.
  # Unicorn is strictly a backend server and therefore does not support
  # the :point_to proxying option.

  class Unicorn < Server

    def initialize app, options={}
      super

      @timeout = options[:timeout] || 3.0

      @supports_rack      = true
      @supports_passenger = false
    end


    def start_cmd
      "cd #{@app.source_path} && #{@bin} -D -E #{@app.deploy_env} "+
        "-p #{@port} -c #{self.config_file_path};"
    end
  end
end
