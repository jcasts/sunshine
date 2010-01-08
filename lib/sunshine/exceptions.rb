module Sunshine

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


  class CmdError < Exception; end


  class SSHCmdError < CmdError
    attr_reader :deploy_server
    def initialize message=nil, deploy_server=nil
      @deploy_server = deploy_server
      super(message)
    end
  end


  class CriticalDeployError < Exception; end

  class FatalDeployError < Exception; end

  class DependencyError < FatalDeployError; end

end
