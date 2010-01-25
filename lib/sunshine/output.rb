module Sunshine

  ##
  # The Output class handles all of the logging to the shell
  # during the Sunshine runtime.

  class Output

    COLORS = {
      Logger::UNKNOWN => :red,
      Logger::FATAL   => :red,
      Logger::ERROR   => :red,
      Logger::WARN    => :yellow,
      Logger::INFO    => :default,
      Logger::DEBUG   => :cyan,
    }

    attr_reader :logger

    def initialize(options={})
      @logger = Logger.new options[:output] || $stdout
      @logger.formatter = lambda{|sev, time, progname, msg| msg}
      @logger.level = options[:level] || Logger::DEBUG
      @indent = 0
    end

    ##
    # Prints messages according to the standard output format.
    # Options supported:
    #   :level:    level of the log message
    #   :indent:  indentation of the message
    def print(title, message, options={})
      severity = options[:level] || Logger::DEBUG
      color = COLORS[severity]
      indent = " " * (options[:indent].to_i * 2)

      print_string = message.split("\n")
      print_string.map!{|m| "#{indent}[#{title}] #{m.chomp}"}
      print_string = "#{print_string.join("\n")} \n"
      print_string = print_string.foreground(color)
      print_string = print_string.bright if indent.empty?

      @logger.add(severity, print_string)
    end

    ##
    # Generic log message which handles log indentation (for clarity).
    # Log indentation if achieved done by passing a block:
    #
    #   output.log("MAIN", "Main thing is happening") do
    #     ...
    #     output.log("SUB1", "Sub process thing") do
    #       ...
    #       output.log("SUB2", "Innermost process thing")
    #     end
    #   end
    #
    #   output.log("MAIN", "Start something else")
    #
    #   ------
    #   > [MAIN] Main thing is happening
    #   >   [SUB1] Sub process thing
    #   >     [SUB2] Innermost process thing
    #   >
    #   > [MAIN] Start something else
    #
    # Log level is set to the instance's default unless
    # specified in the options argument with :level => Logger::LEVEL.
    # The default log level is Logger::INFO
    #
    # Best practice for using log levels is to call the level methods
    # which all work similarly to the log method:
    # unknown, fatal, error, warn, info, debug
    def log(title, message, options={}, &block)
      unless Sunshine.trace?
        return block.call if block_given?
        return
      end

      options = {:indent => @indent}.merge(options)
      self.print(title, message, options)
      if block_given?
        @indent = @indent + 1
        begin
          block.call
        ensure
          @indent = @indent - 1
          @logger << "\n"
        end
      end
    end

    ##
    # Log a message of log level unknown.
    def unknown(title, message, options={}, &block)
      self.log(title, message, options.merge(:level => Logger::UNKNOWN), &block)
    end

    ##
    # Log a message of log level fatal.
    def fatal(title, message, options={}, &block)
      self.log(title, message, options.merge(:level => Logger::FATAL), &block)
    end

    ##
    # Log a message of log level error.
    def error(title, message, options={}, &block)
      self.log(title, message, options.merge(:level => Logger::ERROR), &block)
    end

    ##
    # Log a message of log level warn.
    def warn(title, message, options={}, &block)
      self.log(title, message, options.merge(:level => Logger::WARN), &block)
    end

    ##
    # Log a message of log level info.
    def info(title, message, options={}, &block)
      self.log(title, message, options.merge(:level => Logger::INFO), &block)
    end

    ##
    # Log a message of log level debug.
    def debug(title, message, options={}, &block)
      self.log(title, message, options.merge(:level => Logger::DEBUG), &block)
    end
  end
end
