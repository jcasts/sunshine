module Sunshine

  ##
  # The Console class handles local input, output and execution to the shell.

  class Console

    include Open4

    LOCAL_USER = `whoami`
    SUDO_PROMPT = /^Password:/

    attr_reader :user, :host, :password

    def initialize output = $stdout
      @output = output
      @input = HighLine.new
      @user = LOCAL_USER
      @host = "localhost"
      @password = nil
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
    # Prompt the user for a password

    def prompt_for_password
      @password = ask("#{@user}@#{@host} Password:") do |q|
        q.echo = false
      end
    end


    ##
    # Execute a command on the local system and return the output.
    # Raises CmdError on stderr.

    def run cmd
      execute cmd
    end

    alias call run


    def execute cmd
      result = Hash.new{|h,k| h[k] = []}

      pid, inn, out, err = popen4(*cmd.to_a)

      inn.sync   = true
      streams    = [out, err]

      # Handle process termination ourselves
      status = nil
      Thread.start do
        status = Process.waitpid2(pid).last
      end

      until streams.empty? do
        # don't busy loop
        selected, = select streams, nil, nil, 0.1

        next if selected.nil? or selected.empty?

        selected.each do |stream|
          if stream.eof? then
            streams.delete stream if status # we've quit, so no more writing
            next
          end

          data = stream.readpartial(1024)

          Sunshine.logger.debug ">>", data if stream == out
          Sunshine.logger.error ">>", data if stream == err

          if stream == err && data =~ SUDO_PROMPT then

            unless Sunshine.interactive?
              Process.kill "KILL", pid
              Process.wait
            end

            inn.puts(@password || prompt_for_password)
            data << "\n"
            Sunshine.console << "\n"
          end

          result[stream] << data
        end
      end

      unless status.success? then
        raise CmdError,
          "Execution failed with status #{status.exitstatus}: #{cmd.join ' '}"
      end

      result[out].join.chomp

    ensure
      inn.close rescue nil
      out.close rescue nil
      err.close rescue nil
    end
  end
end
