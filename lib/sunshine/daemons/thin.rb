module Sunshine

  ##
  # Simple server wrapper for Thin setup and control.
  # Thin is considered a backend server and therefore does not support
  # the :point_to proxying option.
  #
  # Note: Thin only supports a single log file. The default stdout file is used.
  #
  # Note: Thin manipulates the passed pid filepath to:
  # path/[basename].[port].pid
  # Sunshine::Thin will adjust the @pid attribute value accordingly.

  class Thin < Server

    def initialize app, options={}
      super

      @start_pid = @pid

      pid_name  = File.basename(@pid, ".pid")
      @pid      = File.join File.dirname(@pid), "#{pid_name}.#{@port}.pid"

      @timeout = options[:timeout] || 3

      @supports_rack = true
      @supports_passenger = false
    end


    def start_cmd
      "cd #{@app.source_path} && "+
        "#{@bin} start -C #{self.config_file_path} -P #{@start_pid};"
    end
  end
end
