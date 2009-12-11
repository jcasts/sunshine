module Sunshine

  class Console

    def initialize(output = STDOUT)
      @output = output
    end

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

    def prompt(text=nil)
      puts text if text
      gets.chomp
    end

    def write(str)
      @output.write(str)
    end

    alias << write

    def close
      @output.close
    end


    def run(str)
      stdin, stdout, stderr = Open3.popen3(str)
      stderr = stderr.read
      raise(CmdError, "#{stderr}  when attempting to run '#{str}'") unless
        stderr.empty?
      stdout.read.strip
    end

  end

end
