module Sunshine

  ##
  # A wrapper for configuring the apache2 server.

  class Apache < Server

    def initialize app, options={}
      super

      @bin = options[:bin] || 'apachectl'

      @sudo = options[:sudo] || @port < 1024

      @dep_name = options[:dep_name] ||
        use_passenger? ? 'passenger-apache' : 'apache2'
    end


    def start_cmd
      "#{@bin} -f #{self.config_file_path}"
    end
  end
end
