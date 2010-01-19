module Sunshine

  ##
  # Healthcheck objects handle enabling and disabling health checking for
  # load balancers by touching health.txt and health.disabled files on
  # an app's deploy servers

  class Healthcheck

    attr_accessor :path, :deploy_servers

    def initialize(path, deploy_servers)
      @path = path
      @deploy_servers = deploy_servers
      @hc_file = "#{@path}/health.txt"
      @hc_disabled_file = "#{@path}/health.disabled"
    end


    ##
    # Disables healthcheck - status: :disabled

    def disable
      Sunshine.logger.info :healthcheck, "Disabling healthcheck" do
        @deploy_servers.each do |deploy_server|
          deploy_server.run "touch #{@hc_disabled_file} && rm -f #{@hc_file}"
        end
      end
    end


    ##
    # Enables healthcheck which should set status to :ok

    def enable
      Sunshine.logger.info :healthcheck, "Enabling healthcheck" do
        @deploy_servers.each do |deploy_server|
          deploy_server.run "rm -f #{@hc_disabled_file} && touch #{@hc_file}"
        end
      end
    end


    ##
    # Remove the healthcheck file - status: :down

    def remove
      Sunshine.logger.info :healthcheck, "Removing healthcheck" do
        @deploy_servers.each do |deploy_server|
          deploy_server.run "rm -f #{@hc_disabled_file} #{@hc_file}"
        end
      end
    end


    ##
    # Get the health status of each deploy server.
    # Returns a hash: {'deployserver' => :status}
    # Status has three states:
    #   :ok:        everything is peachy
    #   :disabled:  healthcheck was explicitely turned off
    #   :down:      um, something may be wrong

    def status
      stat = {}
      @deploy_servers.each do |ds|
        stat[ds.host] = {}
        if ( ds.run "test -f #{@hc_disabled_file}" rescue false )
          stat[ds.host] = :disabled
        elsif ( ds.run "test -f #{@hc_file}" rescue false )
          stat[ds.host] = :ok
        else
          stat[ds.host] = :down
        end
      end
      stat
    end
  end
end
