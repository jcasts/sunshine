module Sunshine

  ##
  # The Output class handles all of the logging to the shell
  # during the Sunshine runtime.
  class Output

    def initialize(options={})
      @logger = Logger.new options[:output] || STDOUT
      @logger.formatter = lambda{|sev, time, progname, msg| msg}
      @logger.level = options[:level] ?
        Logger.const_get(options[:level].to_s.upcase) : Logger::DEBUG
      @indent = 0
      @colors = {
        Logger::UNKNOWN => :red,
        Logger::FATAL   => :red,
        Logger::ERROR   => :red,
        Logger::WARN    => :yellow,
        Logger::INFO    => :default,
        Logger::DEBUG   => :cyan,
      }
    end

    ##
    # Prints messages according to the standard output format.
    # Options supported:
    #   :type:    type/level of the log message
    #   :break:   number of line breaks to insert before the message
    #   :indent:  indentation of the message
    def print(title, message, options={})
      severity = options[:type] ?
        Logger.const_get(options[:type].to_s.upcase) : Logger::DEBUG
      color = @colors[severity]
      new_lines = "\n" * (options[:break] || 0)
      indent = " " * (options[:indent].to_i * 2)

      print_string = message.split("\n")
      print_string.map!{|m| "#{indent}[#{title}] #{m.chomp}"}
      print_string = "#{new_lines}#{print_string.join("\n")} \n"
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
    # specified in the options argument with :type => :some_level.
    # The default log level is :info.
    #
    # Best practice for using log levels is to call the level methods
    # which all work similarly to the log method:
    # unknown, fatal, error, warn, info, debug
    def log(title, message, options={}, &block)
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
    # Log an message of log level unknown.
    def unknown(title, message, options={}, &block)
      self.log(title, message, options.merge(:type => :unknown), &block)
    end

    ##
    # Log an message of log level fatal.
    def fatal(title, message, options={}, &block)
      self.log(title, message, options.merge(:type => :fatal), &block)
    end

    ##
    # Log an message of log level error.
    def error(title, message, options={}, &block)
      self.log(title, message, options.merge(:type => :error), &block)
    end

    ##
    # Log an message of log level warn.
    def warn(title, message, options={}, &block)
      self.log(title, message, options.merge(:type => :warn), &block)
    end

    ##
    # Log an message of log level info.
    def info(title, message, options={}, &block)
      self.log(title, message, options.merge(:type => :info), &block)
    end

    ##
    # Log an message of log level debug.
    def debug(title, message, options={}, &block)
      self.log(title, message, options.merge(:type => :debug), &block)
    end
  end

end
