module Sunshine

  ##
  # A wrapper for configuring the apache2 server.
  # Note: Due to Apache default limitations, the @connections attribute
  # defaults to 256.

  class Apache < Server

    def initialize app, options={}
      super

      @bin = options[:bin] || 'apachectl'

      @sigkill = 'WINCH'

      @supports_rack      = false
      @supports_passenger = true

      @connections = options[:connections] || 256

      @dep_name = options[:dep_name] ||
        use_passenger? ? 'passenger-apache' : 'apache2'
    end


    def start_cmd
      "#{@bin} -f #{self.config_file_path} -E #{log_file :stderr}"
    end


    def setup
      super do |server_app, binder|
        binder.set :max_clients, @max_clients
        yield(server_app, binder) if block_given?
      end
    end
  end
end
