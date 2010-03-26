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
    attr_accessor :sigkill


    # Server objects need only an App object to be instantiated.
    # All Daemon init options are supported plus the following:
    #
    # :port:: port_num - the port to run the server on
    #                    defaults to 80
    #
    # :server_name:: myserver.com - host name used by server
    #                               defaults to nil
    #
    # By default, servers also assign the option :role => :web.

    def initialize app, options={}
      options[:role] ||= :web

      super app, options

      @port          = options[:port] || 80
      @sudo          = options[:sudo] || @port < 1024
      @server_name   = options[:server_name]
      @sigkill       = 'QUIT'
      @supports_rack = false
    end


    ##
    # Check if passenger is required to run the application.
    # Returns true if the server's target is a Sunshine::App

    def use_passenger?
      Sunshine::App === @target && !supports_rack?
    end


    ##
    # Gets the root of the installer passenger gem.

    def self.passenger_root shell
      str     = shell.call "gem list passenger -d"
      version = $1 if str =~ /passenger\s\((.*)\)$/
      gempath = $1 if str =~ /Installed\sat:\s(.*)$/

      return unless version && gempath

      File.join(gempath, "gems/passenger-#{version}")
    end


    ##
    # Add passenger information to the binder at setup time.

    def setup
      super do |server_app, binder|

        binder.forward :use_passenger?

        binder.set :passenger_root do
          Server.passenger_root server_app.shell
        end

        yield(server_app, binder) if block_given?
      end
    end


    ##
    # Default server stop command.

    def stop_cmd
      "test -f #{@pid} && kill -#{@sigkill} $(cat #{@pid}) && sleep 1 && "+
        "rm -f #{@pid} || echo 'No #{@name} process to stop for #{@app.name}';"
    end


    ##
    # Defines if this server supports interfacing with rack.

    def supports_rack?
      @supports_rack
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

        each_server_app do |sa|
          sa.info[:ports][@pid] = @port
        end
      end
    end
  end
end
