module Sunshine

  ##
  # Healthcheck objects handle enabling and disabling health checking for
  # load balancers by touching health.enabled and health.disabled files on
  # an app's shell.

  class Healthcheck

    attr_accessor :shell, :enabled_file, :disabled_file

    def initialize path, shell
      @shell = shell
      @enabled_file = "#{path}/health.enabled"
      @disabled_file = "#{path}/health.disabled"
    end


    ##
    # Disables healthcheck - status: :disabled

    def disable
      @shell.call "touch #{@disabled_file} && rm -f #{@enabled_file}"
    end


    ##
    # Check if healthcheck is disabled.

    def disabled?
      @shell.file? @disabled_file
    end


    ##
    # Check if healthcheck is down.

    def down?
      !@shell.file?(@disabled_file) && !@shell.file?(@enabled_file)
    end


    ##
    # Enables healthcheck which should set status to :ok

    def enable
      @shell.call "rm -f #{@disabled_file} && touch #{@enabled_file}"
    end


    ##
    # Check if healthcheck is enabled.

    def enabled?
      @shell.file? @enabled_file
    end


    ##
    # Remove the healthcheck file - status: :down

    def remove
      @shell.call "rm -f #{@disabled_file} #{@enabled_file}"
    end


    ##
    # Get the health status from the shell.
    # Returns one of three states:
    #   :enabled:   everything is great
    #   :disabled:  healthcheck was explicitely turned off
    #   :down:      um, something is wrong

    def status
      return :disabled if disabled?
      return :enabled  if enabled?
      :down
    end
  end
end
