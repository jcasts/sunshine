module Sunshine

  ##
  # The Console class handles local input, output and execution to the shell.

  class Console

    def initialize(output = $stdout)
      @output = output
      @input = HighLine.new
    end


    ##
    # Prompt the user for input.
    def ask(*args, &block)
      @input.ask(*args, &block)
    end


    ##
    # Write string to stdout (by default).

    def write(str)
      @output.write(str)
    end

    alias << write


    ##
    # Close the output IO. (Required by the Logger class)

    def close
      @output.close
    end


    ##
    # Execute a command on the local system and return the output.
    # Raises CmdError on stderr.

    def run(str)
      result = nil
      Open4.popen4(str) do |pid, stdin, stdout, stderr|
        stderr = stderr.read
        raise(CmdError, "#{stderr}  when attempting to run '#{str}'") unless
          stderr.empty?
        result = stdout.read.chomp
      end
      result
    end

    alias call run

  end
end
