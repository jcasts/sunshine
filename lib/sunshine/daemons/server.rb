module Sunshine

  ##
  # An abstract class to wrap simple server software setup and start/stop.
  #
  # Child classes are expected to at least provide a start and stop bash script
  # by either overloading the start_cmd and stop_cmd methods, or by setting
  # @start_cmd and @stop_cmd. A restart_cmd method or @restart_cmd attribute
  # may also be specified if restart requires more functionality than simply
  # calling start_cmd && stop_cmd.

  class Server < Daemon

    def self.binder_methods
      [:server_name, :port].concat super
    end


    attr_reader :server_name, :port


    # Server objects need only an App object to be instantiated.
    # All Daemon init options are supported plus the following:
    #
    # :port:: port_num - the port to run the server on
    #                    defaults to 80
    #
    # :server_apps:: ds_arr - deploy servers to use
    #
    # :server_name:: myserver.com - host name used by server
    #                               defaults to nil

    def initialize app, options={}
      options[:server_apps] ||= app.find(:role => :web)

      super app, options

      @port        = options[:port] || 80
      @server_name = options[:server_name]
    end


    private

    def config_binding shell
      binder = super

      binder.set :server_name, (@server_name || shell.host)

      binder
    end


    def register_after_user_script
      super

      @app.after_user_script do |app|
        next unless @port

        @server_apps.each do |sa|
          sa.info[:ports][@pid] = @port
        end
      end
    end
  end
end
