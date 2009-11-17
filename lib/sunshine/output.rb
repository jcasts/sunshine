module Sunshine

  class Output

    def initialize(options={})
      @logger = Logger.new(STDOUT)
      @logger.formatter = lambda{|sev, time, progname, msg| msg}
      @logger.level = options[:level] ? Logger.const_get(options[:level].to_s.upcase) : Logger::DEBUG
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

    def print(title, message, options={})
      severity = options[:type] ? Logger.const_get(options[:type].to_s.upcase) : Logger::DEBUG
      color = @colors[severity]
      new_lines = "\n" * (options[:break] || 0)
      indent = " " * (options[:indent].to_i * 2)

      print_string = message.split("\n").map{|m| "#{indent}[#{title}] #{m.chomp}"}
      print_string = "#{new_lines}#{print_string.join("\n")} \n"
      print_string = print_string.foreground(color)
      print_string = print_string.bright if indent.empty?

      @logger.add(severity, print_string)
    end

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

    def unknown(title, message, options={}, &block)
      self.log(title, message, options.merge(:type => :unknown), &block)
    end

    def fatal(title, message, options={}, &block)
      self.log(title, message, options.merge(:type => :fatal), &block)
    end

    def error(title, message, options={}, &block)
      self.log(title, message, options.merge(:type => :error), &block)
    end

    def warn(title, message, options={}, &block)
      self.log(title, message, options.merge(:type => :warn), &block)
    end

    def info(title, message, options={}, &block)
      self.log(title, message, options.merge(:type => :info), &block)
    end

    def debug(title, message, options={}, &block)
      self.log(title, message, options.merge(:type => :debug), &block)
    end
  end

end
