module Sunshine

  ##
  # A standard sunshine exception
  class Exception < StandardError
    def initialize input=nil, message=nil
      if ::Exception === input
        message = [message, input.message].compact.join(": ")
        super(message)
        self.set_backtrace(input.backtrace)
      else
        super(input)
      end
    end
  end


  ##
  # An error occurred when attempting to run a command on the local system
  class CmdError < Exception;
    attr_reader :exit_code

    def initialize exit_code, cmd=nil
      message = "Execution failed with status #{exit_code}: #{cmd}"
      super message
      @exit_code = exit_code
    end
  end


  ##
  # Something went wrong with a deploy-specific item.
  class DeployError < Exception; end


  ##
  # The error is serious enough that deploy cannot proceed.
  # Sunshine will attempt to revert to a previous deploy if available.
  class CriticalDeployError < DeployError; end


  ##
  # The error is so serious that no more action can be taken.
  # Sunshine will attempt to close any ssh connections and stop the deploy.
  class FatalDeployError < DeployError; end

  ##
  # A dependency could not be installed.
  class DependencyError < FatalDeployError; end

end
