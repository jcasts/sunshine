require 'test/test_helper'

class TestDaemon < Test::Unit::TestCase

  def setup
    mock_remote_shell_popen4
    @app    = Sunshine::App.new(TEST_APP_CONFIG_FILE).extend MockObject
    @server_app = @app.server_apps.first.extend MockObject
    @app.server_apps.first.shell.extend MockObject

    use_remote_shell @server_app.shell
  end


  def test_missing_start_cmd
    daemon = Sunshine::Daemon.new @app

    begin
      daemon.start_cmd
      raise "Should have thrown DaemonError but didn't :("
    rescue Sunshine::DaemonError => e
      assert_equal "start_cmd undefined for daemon", e.message
    end
  end

end
