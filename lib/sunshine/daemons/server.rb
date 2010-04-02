module Sunshine

  ##
  # An abstract class to wrap simple server software setup and start/stop.
  #
  # Child classes are expected to at least provide a start_cmd bash script
  # by either overloading the start_cmd method, or by setting @start_cmd.
  # A restart_cmd and stop_cmd method or attribute may also be specified
  # if restart requires more functionality than simply calling
  # start_cmd && stop_cmd.

  class Server < Daemon

    ##
    # Creates a server cluster object:
    #   Mongrel.new_cluster 3, app, :port => 5000
    #   #=> [<# mongrel_5000 >, <# mongrel_5001 >, <# mongrel_5002 >]

    def self.new_cluster count, app, options={}
      ServerCluster.new self, count, app, options
    end


    def self.binder_methods
      [:server_name, :port, :target, :connections].concat super
    end


    attr_reader :server_name, :port, :target, :connections

    attr_accessor :sigkill, :cluster


    # Server objects need only an App object to be instantiated.
    # All Daemon init options are supported plus the following:
    #
    # :connections:: num - Number of connections allowed per server;
    # defaults to 1024.
    #
    # :point_to:: app|server - An app or server to point to,
    # defaults to the passed app. If a server object is given, will
    # act as a proxy. (Only valid on front-end servers - Nginx, Apache)
    #
    # :port:: port_num - The port to run the server on defaults to 80.
    #
    # :server_name:: myserver.com - Host name used by server
    # defaults to the individual remote host.
    #
    # By default, servers also assign the option :role => :web.

    def initialize app, options={}
      options[:role] ||= :web

      super app, options

      @connections   = options[:connections]          || 1024
      @port          = options[:port]                 || 80
      @server_name   = options[:server_name]
      # Setting @sudo to nil will let the server apps' shells handle sudo
      @sudo          = options[:sudo] || @port < 1024 || nil
      @target        = options[:point_to]             || @app

      @supports_rack      = false
      @supports_passenger = false
    end


    ##
    # Check if passenger is required to run the application.
    # Returns true if the server's target is a Sunshine::App and if
    # the server explicitely supports passenger.

    def use_passenger?
      Sunshine::App === @target && supports_passenger? && !supports_rack?
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
    # Adds passenger information to the binder at setup time.

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
    # Defines if this server has passenger support.

    def supports_passenger?
      @supports_passenger
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

      binder.set :proxy_name, "#{@app.name}_proxy"

      binder.set :target_server do
        target.server_name || server_name
      end

      binder
    end


    def register_after_user_script
      super

      @app.after_user_script do |app|
        next unless @port && has_setup?

        each_server_app do |sa|
          sa.info[:ports][@pid] = @port
        end
      end
    end
  end
end
