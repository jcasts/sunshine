require 'test/test_helper'

class TestNginx < Test::Unit::TestCase

  def setup
    @app = Sunshine::App.new TEST_APP_CONFIG_FILE
    @passenger = Sunshine::Nginx.new @app
    @nginx = Sunshine::Nginx.new @app, :port => 5000, :point_to => @passenger
  end


  def test_cmd
    assert_equal start_cmd(@nginx), @nginx.start_cmd
    assert_equal stop_cmd(@nginx), @nginx.stop_cmd
  end


  def test_sudo_cmd
    assert_equal start_cmd(@passenger, true), @passenger.start_cmd
    assert_equal stop_cmd(@passenger, true), @passenger.stop_cmd
  end


  def test_setup
  end


  def start_cmd svr, sudo=false
    sudo = sudo ? "sudo " : ""
    "#{sudo}#{svr.bin} -c #{svr.config_file_path}"
  end

  def stop_cmd svr, sudo=false
    sudo = sudo ? "sudo " : ""
    cmd = "test -f #{svr.pid} && #{sudo}kill -QUIT $(cat #{svr.pid})"+
      " || echo 'No #{svr.name} process to stop for #{svr.app.name}';"
    cmd << "sleep 2 ; rm -f #{svr.pid};"
  end
end
