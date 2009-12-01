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

  end

end
