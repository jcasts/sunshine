require 'test/test_helper'

class TestDeployServer < Test::Unit::TestCase

  def setup
    mock_deploy_server_popen4

    @app = Sunshine::App.new TEST_APP_CONFIG_FILE

    @host = "jcastagna@jcast.np.wc1.yellowpages.com"

    @deploy_server = Sunshine::DeployServer.new @host
    @deploy_server.connect

    use_deploy_server @deploy_server
  end

  def teardown
    @deploy_server.disconnect
  end

  def test_connect
    assert_ssh_call "echo ready; for (( ; ; )); do sleep 100; done"
    assert @deploy_server.connected?
  end

  def test_disconnect
    @deploy_server.disconnect
    assert !@deploy_server.connected?
  end

  def test_run
    @deploy_server.run "echo 'line1'; echo 'line2'"
    assert_ssh_call "echo 'line1'; echo 'line2'"
  end

  def test_run_with_stderr
    @deploy_server.set_mock_response 1, :err => 'this is an error'
    cmd = "echo 'this is an error'"
    @deploy_server.run cmd
    raise "Didn't raise CmdError on stderr"
  rescue Sunshine::CmdError => e
    ssh_cmd = @deploy_server.send(:ssh_cmd, cmd).join(" ")
    assert_equal "Execution failed with status 1: #{ssh_cmd}", e.message
  end

  def test_upload
    @deploy_server.upload "test/fixtures/sunshine_test", "sunshine_test"
    assert_rsync "test/fixtures/sunshine_test",
      "#{@deploy_server.host}:sunshine_test"
  end

  def test_download
    @deploy_server.download "sunshine_test", "."
    assert_rsync "#{@deploy_server.host}:sunshine_test", "."
  end

  def test_make_file
    @deploy_server.make_file("some_dir/sunshine_test_file", "test data")
    tmp_file = "#{Sunshine::DeployServer::TMP_DIR}/sunshine_test_file"
    assert_rsync(/^#{tmp_file.gsub("+",'\\\+')}_[0-9]+/,
      "#{@deploy_server.host}:some_dir/sunshine_test_file")
  end

  def test_os_name
    @deploy_server.os_name
    assert_ssh_call "uname -s"
  end

  def test_equality
    ds_equal = Sunshine::DeployServer.new @host
    ds_diff1 = Sunshine::DeployServer.new @host, :user => "blarg"
    ds_diff2 = Sunshine::DeployServer.new "some_other_host"

    assert_equal ds_equal, @deploy_server
    assert_equal ds_diff1, @deploy_server
    assert ds_diff2 != @deploy_server
  end

  def test_file?
    @deploy_server.file? "some/file/path"
    assert_ssh_call "test -f some/file/path"
  end

  def test_symlink
    @deploy_server.symlink "target_file", "sym_name"
    assert_ssh_call "ln -sfT target_file sym_name"
  end

end
