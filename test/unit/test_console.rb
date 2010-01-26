require 'test/test_helper'

class TestConsole < Test::Unit::TestCase

  def setup
    @output = StringIO.new
    @output.extend MockObject

    @console = Sunshine::Console.new @output
    @console.extend MockOpen4

    @console.input.extend MockObject
    @console.input.mock :ask, :return => "someinput"
  end


  def test_initialize
    assert_equal @output, @console.output
    assert_equal HighLine, @console.input.class
    assert_equal `whoami`.chomp, @console.user
    assert_equal `hostname`.chomp, @console.host
  end


  def test_ask
    @console.ask "input something!"
    assert 1, @console.input.method_call_count(:ask)
  end


  def test_close
    @console.close
    assert 1, @console.output.method_call_count(:close)
  end


  def test_write
    @console.write "blah"
    assert @output.method_called?(:write, :args => "blah")
  end


  def test_prompt_for_password
    @console.prompt_for_password

    args = "#{@console.user}@#{@console.host} Password:"
    assert @console.input.method_called?(:ask, :args => args)
    assert_equal "someinput", @console.password
  end


  def test_execute
    @console.set_mock_response 0, "say hi"   => [:out, "hi\n"]

    response = @console.execute("say hi") do |stream, data|
      assert_equal :out, stream
      assert_equal "hi\n", data
    end
    assert_equal "hi", response
  end


  def test_execute_errorstatus
    @console.set_mock_response 1, "error me" => [:err, "ERROR'D!"]

    begin
      @console.execute("error me") do |stream, data|
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
    @console.set_mock_response 0, "stderr"   => [:err, "fake error"]

    response = @console.execute("stderr") do |stream, data|
      assert_equal :err, stream
      assert_equal "fake error", data
    end
    assert_equal "", response
  end


  def test_execute_password_prompt
    @console.set_mock_response 0, "do that thing" => [:err, "Password:"]
    @console.input.mock :ask, :return => "new_password"

    @console.execute("do that thing")
    assert_equal "new_password", @console.password
  end
end
