module Sunshine

  ##
  # A wrapper for configuring the apache2 server.
  # Warning: Unlike Nginx or Unicorn,  setting the :pid option won't
  # actually define where the pid should live.
  # It will instead define where Sunshine should look to check if the process
  # is running. A bad pid location will result in faulty Sunshine assumptions
  # on the status of the apache server.

  class Apache < Server

    def initialize app, options={}
      options[:bin]      ||= 'apachectl'
      options[:pid]      ||= '/usr/local/apache2/logs/httpd.pid'

      super

      @sudo = options[:sudo] || @port < 1024

      @dep_name = options[:dep_name] ||
        use_passenger? ? 'passenger-apache' : 'apache2'
    end


    def start_cmd
      @bin
    end


    def stop_cmd
      "#{@bin} -k stop"
    end


    def restart_cmd
      "#{@bin} -k restart"
    end


    def use_passenger?
      Sunshine::App === @target
    end
  end
end
