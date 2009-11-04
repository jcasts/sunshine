require 'test/test_helper'

class TestDeployServer < Test::Unit::TestCase

  def setup
    @app = Sunshine::App.new TEST_APP_CONFIG_FILE
    @deploy_server = Sunshine::DeployServer.new("nextgen@np4.wc1.yellowpages.com", @app)
  end

  def teardown
    @deploy_server.disconnect
  end

  def test_connect
    @deploy_server.connect
    assert @deploy_server.connected?
  end

  def test_disconnect
    @deploy_server.connect
    @deploy_server.disconnect
    assert !@deploy_server.connected?
  end

  def test_run
    @deploy_server.connect
    assert_equal "test", @deploy_server.run("echo 'test'").strip
  end

  def test_run_with_block
  end

  def test_run_with_stderr
  end

end
