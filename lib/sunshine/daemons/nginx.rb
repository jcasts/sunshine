module Sunshine

  ##
  # Simple server wrapper for nginx setup and control.

  class Nginx < Server

    def initialize app, options={}
      super

      @sudo = options[:sudo] || @port < 1024

      @dep_name = options[:dep_name] ||
        use_passenger? ? 'passenger-nginx' : 'nginx'
    end


    def start_cmd
      "#{@bin} -c #{self.config_file_path}"
    end
  end
end
