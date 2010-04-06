module MockOpen4

  CMD_RETURN = {
    Sunshine::RemoteShell::LOGIN_LOOP => [:out, "ready\n"]
  }

  attr_reader :cmd_log

  def popen4(*args)
    cmd = args.join(" ")
    @cmd_log ||= []
    @cmd_log << cmd


    pid = "test_pid"
    inn_w = StringIO.new
    out_r, out_w = IO.pipe
    err_r, err_w = IO.pipe

    ios = {:inn => inn_w, :out => out_w, :err => err_w}
    stream, string = output_for cmd

    ios[stream].write string
    out_w.write nil
    err_w.write nil

    out_w.close
    err_w.close

    if block_given?
      yield
      inn_w.close
      out_r.close
      err_r.close
    end

    return pid, inn_w, out_r, err_r
  end

  def output_for(cmd)
    @mock_output ||= {}
    if @mock_output
      output = @mock_output[cmd]
      output ||= @mock_output[nil].shift if Array === @mock_output[nil]
      @mock_output.delete(cmd)
      if output
        Process.set_exitcode output.delete(output.last)
        return output
      end
    end

    CMD_RETURN.each do |cmd_key, return_val|
      return return_val if cmd.include? cmd_key
    end
    return :out, "some_value"
  end

  def set_mock_response code, stream_vals={}, options={}
    @mock_output ||= {}
    @mock_output[nil] ||= []
    new_stream_vals = {}

    stream_vals.each do |key, val|
      if Symbol === key
        @mock_output[nil] << [key, val, code]
        next
      end

      if Sunshine::RemoteShell === self
        key = build_remote_cmd(key, options).join(" ")
      end

      new_stream_vals[key] = (val.dup << code)
    end
    @mock_output.merge! new_stream_vals
  end

end


class StatusStruct < Struct.new("Status", :exitstatus)
  def success?
    self.exitstatus == 0
  end
end


Process.class_eval do
  class << self

    def set_exitcode(code)
      @exit_code = code
    end

    alias old_waitpid2 waitpid2
    undef waitpid2

    def waitpid2(*args)
      pid = args[0]
      if pid == "test_pid"
        exitcode = @exit_code ||= 0
        @exit_code = 0
        return [StatusStruct.new(exitcode)]
      else
        return old_waitpid2(*args)
      end
    end

    alias old_kill kill
    undef kill

    def kill(type, pid)
      return true if type == 0 && pid == "test_pid"
      old_kill(type, pid)
    end
  end
end
