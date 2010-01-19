module MockOpen4

  LOGIN_CMD = "echo ready;"

  CMD_RETURN = {
    LOGIN_CMD => [:out, "ready\n"]
  }

  attr_reader :cmd_log

  def popen4(*args)
    cmd = args.join(" ")
    @cmd_log ||= []
    @cmd_log << cmd


    pid = "test_pid"
    inn_r, inn_w = IO.pipe
    out_r, out_w = IO.pipe
    err_r, err_w = IO.pipe

    ios = {:inn => inn_w, :out => out_w, :err => err_w}
    stream, string = output_for cmd
    ios[stream].write string
    out_w.write nil
    err_w.write nil

    inn_r.close
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
      return output if output
    end

    CMD_RETURN.each do |cmd_key, return_val|
      return return_val if cmd.include? cmd_key
    end
    return :out, "some_value"
  end

  def set_mock_response code, stream_vals={}
    Process.set_exitcode code
    @mock_output ||= {}
    @mock_output[nil] ||= []
    if Sunshine::DeployServer === self
      stream_vals = stream_vals.dup

      stream_vals.each do |key, val|
        if Symbol === key
          @mock_output[nil] << [key, val]
          stream_vals.delete(key)
          next
        end

        stream_vals.delete(key)
        key = ssh_cmd(key).join(" ")

        stream_vals[key] = val
      end
    end
    @mock_output.merge! stream_vals
  end

end


class StatusStruct < Struct.new("Status", :exitstatus)
  def success?
    self.exitstatus == 0
  end
end


Process.class_eval do

  def self.set_exitcode(code)
    @exit_code = code
  end

  alias old_waitpid2 waitpid2

  def self.waitpid2(*args)
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

  def self.kill(type, pid)
    return true if type == 0 && pid == "test_pid"
    old_kill(type, pid)
  end
end
