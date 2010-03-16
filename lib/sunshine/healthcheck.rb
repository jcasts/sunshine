module Sunshine

  ##
  # Healthcheck objects handle enabling and disabling health checking for
  # load balancers by touching health.txt and health.disabled files on
  # an app's deploy servers

  class Healthcheck

    attr_reader :shells, :enabled_file, :disabled_file

    def initialize path, shells
      @shells = [*shells]
      @enabled_file = "#{path}/health.txt"
      @disabled_file = "#{path}/health.disabled"
    end


    ##
    # Disables healthcheck - status: :disabled

    def disable
      Sunshine.logger.info :healthcheck, "Disabling healthcheck" do
        @shells.each do |shell|
          shell.call "touch #{@disabled_file} && rm -f #{@enabled_file}"
        end
      end
    end


    ##
    # Enables healthcheck which should set status to :ok

    def enable
      Sunshine.logger.info :healthcheck, "Enabling healthcheck" do
        @shells.each do |shell|
          shell.call "rm -f #{@disabled_file} && touch #{@enabled_file}"
        end
      end
    end


    ##
    # Remove the healthcheck file - status: :down

    def remove
      Sunshine.logger.info :healthcheck, "Removing healthcheck" do
        @shells.each do |shell|
          shell.call "rm -f #{@disabled_file} #{@enabled_file}"
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

    def status shells=@shells
      stat = {}
      [*shells].each do |shell|
        stat[shell.host] = {}
        if ( shell.call "test -f #{@disabled_file}" rescue false )
          stat[shell.host] = :disabled
        elsif ( shell.call "test -f #{@enabled_file}" rescue false )
          stat[shell.host] = :ok
        else
          stat[shell.host] = :down
        end
      end
      stat
    end
  end
end
