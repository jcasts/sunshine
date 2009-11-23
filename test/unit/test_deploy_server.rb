require 'test/test_helper'

# TODO: abstract hitting a live server to something else.
class TestDeployServer < Test::Unit::TestCase

  def setup
    @app = Sunshine::App.new TEST_APP_CONFIG_FILE
    @deploy_server = Sunshine::DeployServer.new("nextgen@np4.wc1.yellowpages.com")
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
    assert_equal "line1\nline2\n", @deploy_server.run("echo 'line1'; echo 'line2'")
  end

  def test_run_with_block
    @deploy_server.run("echo 'line1'; echo 'line2'") do |stream, data|
      assert_equal :stdout, stream
      assert_equal "line1\nline2\n", data
    end
  end

  def test_run_with_stderr
    @deploy_server.run("echo 'this is an error' 1>&2")
    raise "Didn't raise SSHCmdError on stderr stream"
  rescue Sunshine::SSHCmdError => e
    assert_equal "this is an error\n", e.message
    assert_equal @deploy_server, e.deploy_server
  end

  def test_upload
    @deploy_server.upload("test/fixtures/sunshine_test", "sunshine_test", :recursive => true)
    test = @deploy_server.run "test -f sunshine_test/test_upload && echo 'true' || echo 'false'"
    assert_equal "true\n", test
    @deploy_server.run "rm -rf sunshine_test"
  end

  def test_download
    @deploy_server.upload("test/fixtures/sunshine_test", "sunshine_test", :recursive => true)
    @deploy_server.download("sunshine_test", ".", :recursive => true)
    assert File.exists?("sunshine_test/test_upload")
    @deploy_server.run "rm -rf sunshine_test"
    FileUtils.rm_rf "sunshine_test"
  end

  def test_make_file
    @deploy_server.make_file("sunshine_test_file", "test data")
    file_read = @deploy_server.run "cat sunshine_test_file"
    assert_equal "test data", file_read
    @deploy_server.run "rm sunshine_test_file"
  end

  def test_os_name
    assert_equal "linux", @deploy_server.os_name
  end

end
