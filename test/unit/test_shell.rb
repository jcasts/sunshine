require 'test/test_helper'

class TestShell < Test::Unit::TestCase

  def setup
    @output = StringIO.new
    @output.extend MockObject

    @shell = Sunshine::Shell.new @output
    @shell.extend MockOpen4

    @shell.input.extend MockObject
    @shell.input.mock :ask, :return => "someinput"
  end


  def test_initialize
    assert_equal @output, @shell.output
    assert_equal HighLine, @shell.input.class
    assert_equal `whoami`.chomp, @shell.user
    assert_equal `hostname`.chomp, @shell.host
  end


  def test_ask
    @shell.ask "input something!"
    assert_equal 1, @shell.input.method_call_count(:ask)
  end


  def test_close
    @shell.close
    assert_equal 1, @shell.output.method_call_count(:close)
  end


  def test_write
    @shell.write "blah"
    assert @output.method_called?(:write, :args => "blah")
  end


  def test_prompt_for_password
    @shell.prompt_for_password

    args = "#{@shell.user}@#{@shell.host} Password:"
    assert @shell.input.method_called?(:ask, :args => args)
    assert_equal "someinput", @shell.password
  end


  def test_execute
    @shell.set_mock_response 0, "say hi"   => [:out, "hi\n"]

    response = @shell.execute("say hi") do |stream, data|
      assert_equal :out, stream
      assert_equal "hi\n", data
    end
    assert_equal "hi", response
  end


  def test_execute_errorstatus
    @shell.set_mock_response 1, "error me" => [:err, "ERROR'D!"]

    begin
      @shell.execute("error me") do |stream, data|
        assert_equal :err, stream
        assert_equal "ERROR'D!", data
      end
      raise "Didn't call CmdError when it should have"
    rescue Sunshine::CmdError => e
      msg = "Execution failed with status 1: error me"
      assert_equal msg, e.message
    end
  end


  def test_execute_stderronly
    @shell.set_mock_response 0, "stderr"   => [:err, "fake error"]

    response = @shell.execute("stderr") do |stream, data|
      assert_equal :err, stream
      assert_equal "fake error", data
    end
    assert_equal "", response
  end


  def test_execute_password_prompt
    @shell.set_mock_response 0, "do that thing" => [:err, "Password:"]
    @shell.input.mock :ask, :return => "new_password"

    @shell.execute("do that thing")
    assert_equal "new_password", @shell.password
  end
end
