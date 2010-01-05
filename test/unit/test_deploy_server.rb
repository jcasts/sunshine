require 'test/test_helper'

class TestDeployServer < Test::Unit::TestCase

  def setup
    mock_deploy_server_popen4
    @host = "jcastagna@jcast.np.wc1.yellowpages.com"
    @app = Sunshine::App.new TEST_APP_CONFIG_FILE
    @deploy_server = Sunshine::DeployServer.new @host
    @deploy_server.connect
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
    set_popen4_exitcode 1
    cmd = "echo 'this is an error'"
    @deploy_server.run cmd
    raise "Didn't raise CmdError on stderr"
  rescue Sunshine::CmdError => e
    ssh_cmd = @deploy_server.send(:build_ssh_cmd, cmd).join(" ")
    assert_equal "Execution failed with status 1: #{ssh_cmd}", e.message
  end

  def test_upload
    @deploy_server.upload "test/fixtures/sunshine_test", "sunshine_test"
    assert_rsync "test/fixtures/sunshine_test", "#{@host}:sunshine_test"
  end

  def test_download
    @deploy_server.download "sunshine_test", "."
    assert_rsync "#{@host}:sunshine_test", "."
  end

  def test_make_file
    @deploy_server.make_file("some_dir/sunshine_test_file", "test data")
    tmp_file = "#{Sunshine::DeployServer::TMP_DIR}/sunshine_test_file"
    assert_rsync(/^#{tmp_file}_[0-9]+/, "#{@host}:some_dir/sunshine_test_file")
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
    assert ds_diff1 != @deploy_server
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


  def assert_ssh_call(expected)
    ds = @deploy_server
    received = ds.cmd_log.last
    expected = expected.gsub(/'/){|s| "'\\''"}
    expected = "ssh #{ds.ssh_flags.join(" ")} #{ds.host} sh -c '#{expected}'"
    assert_equal expected, received
  end

  def assert_rsync(from, to)
    ds = @deploy_server
    received = ds.cmd_log.last
    rsync_cmd = "rsync -azP -e \"ssh #{ds.ssh_flags.join(' ')}\""
    if Regexp === from
      received_from = received.split(" ")[-2]
      assert received_from =~ from,
        "#{received_from} did not match #{from.inspect}"
      assert_equal to, received.split(" ").last
      assert_equal 0, received.index(rsync_cmd)
    else
      expected = "#{rsync_cmd} #{from} #{to}"
      assert_equal expected, received
    end
  end

end
