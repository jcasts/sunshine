require 'test/test_helper'

class TestDeployServer < Test::Unit::TestCase

  def setup
    @app = Sunshine::App.new TEST_APP_CONFIG_FILE
    @deploy_server = Sunshine::DeployServer.new("nextgen@np4.wc1.yellowpages.com", @app)
    @deploy_server.connect
  end

  def teardown
    @deploy_server.disconnect
  end

  def test_connect
    assert @deploy_server.connected?
  end

  def test_disconnect
    @deploy_server.disconnect
    assert !@deploy_server.connected?
  end

  def test_run
    assert_equal "test\n", @deploy_server.run("echo 'test'")
  end

  def test_run_with_block
    i = 0
    @deploy_server.run("echo 'line1'; echo 'line2'") do |stream, data|
      i = i.next
      assert_equal :stdout, stream
      assert_equal "line#{i}\n", data
    end
  end

  def test_run_with_stderr
  end

  def test_os_name
    assert_equal "linux", @deploy_server.os_name
  end

end
