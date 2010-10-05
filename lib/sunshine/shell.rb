module Sunshine

  ##
  # The Shell class handles local input, output and execution to the shell.

  class Shell

    include Open4

    LOCAL_USER = `whoami`.chomp
    LOCAL_HOST = `hostname`.chomp

    SUDO_FAILED = /^Sorry, try again./
    SUDO_PROMPT = /^Password:/

    attr_reader :user, :host, :password, :input, :output, :mutex
    attr_accessor :env, :sudo, :timeout

    def initialize output = $stdout, options={}
      @output = output

      $stdin.sync
      @input = HighLine.new $stdin

      @user = LOCAL_USER
      @host = LOCAL_HOST

      @sudo     = options[:sudo]
      @env      = options[:env] || {}
      @password = options[:password]

      @timeout = options[:timeout] || Sunshine.timeout

      @mutex = nil
    end


    ##
    # Checks for equality

    def == shell
      @host == shell.host && @user == shell.user rescue false
    end


    ##
    # Prompt the user for input.

    def ask(*args, &block)
      sync{ @input.ask(*args, &block) }
    end


    ##
    # Prompt the user to agree.

    def agree(*args, &block)
      sync{ @input.agree(*args, &block) }
    end


    ##
    # Execute a command on the local system and return the output.

    def call cmd, options={}, &block
      Sunshine.logger.info @host, "Running: #{cmd}" do
        execute sudo_cmd(cmd, options), &block
      end
    end


    ##
    # Prompt the user to make a choice.

    def choose &block
      sync{ @input.choose(&block) }
    end


    ##
    # Close the output IO. (Required by the Logger class)

    def close
      @output.close
    end


    ##
    # Returns true. Compatibility method with RemoteShell.

    def connect
      true
    end


    ##
    # Returns true. Compatibility method with RemoteShell.

    def connected?
      true
    end


    ##
    # Returns true. Compatibility method with RemoteShell.

    def disconnect
      true
    end


    ##
    # Copies a file. Compatibility method with RemoteShell.

    def download from_path, to_path, options={}, &block
      Sunshine.logger.info @host, "Copying #{from_path} -> #{to_path}" do
        FileUtils.cp_r from_path, to_path
      end
    end

    alias upload download


    ##
    # Expands the path. Compatibility method with RemoteShell.

    def expand_path path
      File.expand_path path
    end


    ##
    # Checks if file exists. Compatibility method with RemoteShell.

    def file? filepath
      File.file? filepath
    end


    ##
    # Start an interactive shell with preset permissions and env.
    # Optionally pass a command to be run first.

    def tty! cmd=nil
      sync do
        cmd = [cmd, "sh -il"].compact.join " && "
        pid = fork do
          exec sudo_cmd(env_cmd(cmd)).to_a.join(" ")
        end
        Process.waitpid pid
      end
    end


    ##
    # Write a file. Compatibility method with RemoteShell.

    def make_file filepath, content, options={}
      File.open(filepath, "w+"){|f| f.write(content)}
    end


    ##
    # Get the name of the OS

    def os_name
      @os_name ||= call("uname -s").strip.downcase
    end


    ##
    # Prompt the user for a password

    def prompt_for_password
      host_info = [@user, @host].compact.join("@")
      @password = ask("#{host_info} Password:") do |q|
        q.echo = false
      end
    end


    ##
    # Build an env command if an env_hash is passed

    def env_cmd cmd, env_hash=@env
      if env_hash && !env_hash.empty?
        env_vars = env_hash.map{|e| e.join("=")}
        cmd = ["env", env_vars, cmd].flatten
      end
      cmd
    end


    ##
    # Wrap command in quotes and escape as needed.

    def quote_cmd cmd
      cmd = [*cmd].join(" ")
      "'#{cmd.gsub(/'/){|s| "'\\''"}}'"
    end


    ##
    # Build an sh -c command

    def sh_cmd cmd
      ["sh", "-c", quote_cmd(cmd)]
    end


    ##
    # Build a command with sudo.
    # If sudo_val is nil, it is considered to mean "pass-through"
    # and the default shell sudo will be used.
    # If sudo_val is false, the cmd will be returned unchanged.
    # If sudo_val is true, the returned command will be prefaced
    # with sudo -H
    # If sudo_val is a String, the command will be prefaced
    # with sudo -H -u string_value

    def sudo_cmd cmd, sudo_val=nil
      sudo_val = sudo_val[:sudo] if Hash === sudo_val
      sudo_val = @sudo if sudo_val.nil?

      case sudo_val
      when true
        ["sudo", "-H", cmd].flatten
      when String
        ["sudo", "-H", "-u", sudo_val, cmd].flatten
      else
        cmd
      end
    end


    ##
    # Force symlinking a directory.

    def symlink target, symlink_name
      call "ln -sfT #{target} #{symlink_name}" rescue false
    end


    ##
    # Synchronize a block with the current mutex if it exists.

    def sync
      if @mutex
        @mutex.synchronize{ yield }
      else
        yield
      end
    end


    ##
    # Returns true if command was run successfully, otherwise returns false.

    def syscall cmd, options=nil
      call(cmd, options) && true rescue false
    end


    ##
    # Checks if timeout occurred.

    def timed_out? start_time, max_time=@timeout
      return unless max_time
      Time.now.to_i - start_time.to_i > max_time
    end


    ##
    # Execute a block while setting the shell's mutex.
    # Sets the mutex to its original value on exit.
    # Executing commands with a mutex is used for user prompts.

    def with_mutex mutex
      old_mutex, @mutex = @mutex, mutex
      yield
      @mutex = old_mutex
    end


    ##
    # Runs the passed block within a connection session.
    # If the shell is already connected, connecting and disconnecting
    # is ignored; otherwise, the session method will ensure that
    # the shell's connection gets closed after the block has been
    # executed.

    def with_session
      prev_connection = connected?
      connect unless prev_connection

      yield

      disconnect unless prev_connection
    end


    ##
    # Write string to stdout (by default).

    def write str
      @output.write str
    end

    alias << write


    ##
    # Execute a command with open4 and loop until the process exits.
    # The cmd argument may be a string or an array. If a block is passed,
    # it will be called when data is received and passed the stream type
    # and stream string value:
    #   shell.execute "test -s 'blah' && echo 'true'" do |stream, str|
    #     stream    #=> :stdout
    #     string    #=> 'true'
    #   end
    #
    # The method returns the output from the stdout stream by default, and
    # raises a CmdError if the exit status of the command is not zero.

    def execute cmd
      cmd = [cmd] unless Array === cmd
      pid, inn, out, err = popen4(*cmd)

      inn.sync = true
      log_methods = {out => :debug, err => :error}

      result, status = process_streams(pid, out, err) do |stream, data|
        stream_name = :out if stream == out
        stream_name = :err if stream == err
        stream_name = :inn if stream == inn


        # User blocks should run with sync threads to avoid badness.
        sync do
          Sunshine.logger.send log_methods[stream],
            "#{@host}:#{stream_name}", data

          yield(stream_name, data, inn) if block_given?
        end


        if password_required?(stream_name, data) then

          kill_process(pid) unless Sunshine.interactive?

          send_password_to_stream(inn, data)
        end
      end

      raise_command_failed(status, cmd) unless status.success?

      result[out].join.chomp

    ensure
      inn.close rescue nil
      out.close rescue nil
      err.close rescue nil
    end


    private

    def raise_command_failed(status, cmd)
      err = CmdError.new status.exitstatus, [*cmd].join(" ")
      raise err
    end


    def password_required? stream_name, data
      stream_name == :err && data =~ SUDO_PROMPT
    end


    def send_password_to_stream inn, data
      prompt_for_password if data =~ SUDO_FAILED
      inn.puts @password || prompt_for_password
    end


    def kill_process pid, kill_type="KILL"
      begin
        Process.kill kill_type, pid
        Process.wait
      rescue
      end
    end


    def process_streams pid, *streams
      result = Hash.new{|h,k| h[k] = []}
      start_time = Time.now

      # Handle process termination ourselves
      status = nil
      Thread.start do
        status = Process.waitpid2(pid).last
      end

      until streams.empty? do
        # don't busy loop
        selected, = select streams, nil, nil, 0.1

        raise TimeoutError if timed_out? start_time

        next if selected.nil? or selected.empty?

        selected.each do |stream|

          start_time = Time.now

          if stream.eof? then
            streams.delete stream if status # we've quit, so no more writing
            next
          end

          data = stream.readpartial(1024)

          yield(stream, data)

          result[stream] << data
        end
      end

      return result, status
    end
  end
end
