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
  # A shell command timed out.
  class TimeoutError < Exception; end


  ##
  # Remote connection to server failed.
  class ConnectionError < Exception; end


  ##
  # Something went wrong with a deploy-specific item.
  class DeployError < Exception; end


  ##
  # Something went wrong with a daemon-specific item.
  class DaemonError < Exception; end


  ##
  # Something went wrong with a dependency-specific item.
  class DependencyError < Exception; end


  ##
  # Dependency requested could not be found.
  class MissingDependency < DependencyError; end


  ##
  # Dependency failed to install.
  class InstallError < DependencyError; end

  ##
  # Dependency failed to uninstall.
  class UninstallError < DependencyError; end

  ##
  # Something went wrong with a scm-specific item.
  class RepoError < Exception; end
end
