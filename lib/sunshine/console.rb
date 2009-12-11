module Sunshine

  ##
  # The Console class handles local input, output and execution to the shell.
  class Console

    def initialize(output = STDOUT)
      @output = output
    end

    ##
    # Prompt the user with a hidden input (e.g. for passwords).
    def hidden_prompt(text=nil)
      puts text if text
      input = ''
      begin
        system "stty -echo"
        input = gets.chomp
      ensure
        system "stty echo"
      end
      input
    end

    ##
    # Prompt the user for input.
    def prompt(text=nil)
      puts text if text
      gets.chomp
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
      stdin, stdout, stderr = Open3.popen3(str)
      stderr = stderr.read
      raise(CmdError, "#{stderr}  when attempting to run '#{str}'") unless
        stderr.empty?
      stdout.read.chomp
    end

  end

end
