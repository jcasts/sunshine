module Sunshine

  ##
  # A standard sunshine exception
  class Exception < StandardError
    def initialize input=nil, message=nil
      if Exception === input
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
  class CmdError < Exception; end


  ##
  # An ssh call returned a non-zero exit code
  class SSHCmdError < CmdError
    attr_reader :deploy_server
    def initialize message=nil, deploy_server=nil
      @deploy_server = deploy_server
      super(message)
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
  # The error is so serious that all no more action can be taken.
  # Sunshine will attempt to close any ssh connections and stop the deploy.
  class FatalDeployError < DeployError; end

  ##
  # A dependency could not be installed.
  class DependencyError < FatalDeployError; end

end
