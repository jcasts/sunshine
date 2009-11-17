module Sunshine

  class Output

    def initialize(options={})
      @logger = Logger.new(STDOUT)
      @logger.formatter = lambda{|sev, time, progname, msg| msg}
      @logger.level = options[:level] || Logger::DEBUG
      @indent = 0
      @colors = {
        Logger::UNKNOWN => :red,
        Logger::FATAL   => :red,
        Logger::ERROR   => :red,
        Logger::WARN    => :yellow,
        Logger::INFO    => :green,
        Logger::DEBUG   => :default,
      }
    end

    def print(title, message, options={})
      severity = options[:type] ? Logger.const_get(options[:type].to_s.upcase) : Logger::DEBUG
      new_lines = "\n" * (options[:break] || 1)
      indent = " " * (options[:indent].to_i * 2)
      print_string = "#{new_lines}#{indent}[#{title}] #{message}\n"
      @logger.add(severity, print_string.color(@colors[severity]))
    end

    def log(title, message, options={}, &block)
      if block_given?
        @indent = @indent + 1
        block_options = {
          :indent => @indent,
          :break  => (@indent == 0 ? 1 : 0)
        }
        self.print(title, message, block_options.merge(options))
        begin
          block.call
        ensure
          @indent = @indent - 1
        end
      else
        self.print(title, message, options)
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
