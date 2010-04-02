require 'test/test_helper'

class TestRemoteShell < Test::Unit::TestCase

  def setup
    mock_remote_shell_popen4

    @app = Sunshine::App.new TEST_APP_CONFIG_FILE

    @host = "user@some_server.com"

    @remote_shell = mock_remote_shell @host
  end

  def teardown
    @remote_shell.disconnect
  end

  def test_connect
    assert_ssh_call \
      "echo connected; echo ready; for (( ; ; )); do sleep 10; done"
    assert @remote_shell.connected?
  end

  def test_disconnect
    @remote_shell.disconnect
    assert !@remote_shell.connected?
  end

  def test_call
    @remote_shell.call "echo 'line1'; echo 'line2'"
    assert_ssh_call "echo 'line1'; echo 'line2'"

    @remote_shell.sudo = "sudouser"
    @remote_shell.call "sudocall"
    assert_ssh_call "sudocall", @remote_shell, :sudo => "sudouser"
  end

  def test_call_with_stderr
    @remote_shell.set_mock_response 1, :err => 'this is an error'
    cmd = "echo 'this is an error'"
    @remote_shell.call cmd
    raise "Didn't raise CmdError on stderr"
  rescue Sunshine::CmdError => e
    ssh_cmd = @remote_shell.send(:ssh_cmd, cmd).join(" ")
    assert_equal "Execution failed with status 1: #{ssh_cmd}", e.message
  end

  def test_upload
    @remote_shell.upload "test/fixtures/sunshine_test", "sunshine_test"
    assert_rsync "test/fixtures/sunshine_test",
      "#{@remote_shell.host}:sunshine_test"

    @remote_shell.sudo = "blah"
    @remote_shell.upload "test/fixtures/sunshine_test", "sunshine_test"
    assert_rsync "test/fixtures/sunshine_test",
      "#{@remote_shell.host}:sunshine_test", @remote_shell, "blah"
  end

  def test_download
    @remote_shell.download "sunshine_test", "."
    assert_rsync "#{@remote_shell.host}:sunshine_test", "."

    @remote_shell.download "sunshine_test", ".", :sudo => "sudouser"
    assert_rsync "#{@remote_shell.host}:sunshine_test", ".",
      @remote_shell, "sudouser"
  end

  def test_make_file
    @remote_shell.make_file("some_dir/sunshine_test_file", "test data")
    tmp_file = "#{Sunshine::TMP_DIR}/sunshine_test_file"
    tmp_file = Regexp.escape tmp_file
    assert_rsync(/^#{tmp_file}_[0-9]+/,
      "#{@remote_shell.host}:some_dir/sunshine_test_file")
  end

  def test_os_name
    @remote_shell.os_name
    assert_ssh_call "uname -s"
  end

  def test_equality
    ds_equal = Sunshine::RemoteShell.new @host
    ds_diff1 = Sunshine::RemoteShell.new @host, :user => "blarg"
    ds_diff2 = Sunshine::RemoteShell.new "some_other_host"

    assert_equal ds_equal, @remote_shell
    assert_equal ds_diff1, @remote_shell
    assert ds_diff2 != @remote_shell
  end

  def test_file?
    @remote_shell.file? "some/file/path"
    assert_ssh_call "test -f some/file/path"
  end

  def test_symlink
    @remote_shell.symlink "target_file", "sym_name"
    assert_ssh_call "ln -sfT target_file sym_name"
  end

end
