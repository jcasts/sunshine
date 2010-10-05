require 'test/test_helper'

class TestNginx < Test::Unit::TestCase

  def setup
    @app = Sunshine::App.new TEST_APP_CONFIG_FILE
    @app.server_apps.first.extend MockOpen4
    @app.server_apps.first.shell.extend MockOpen4
    use_remote_shell @app.server_apps.first.shell

    @passenger = Sunshine::Nginx.new @app
    @nginx = Sunshine::Nginx.new @app, :port => 5000, :point_to => @passenger

    @passenger_root = "/Library/Ruby/Gems/1.8/gems/passenger-2.2.11"

    @nginx_passenger_check = "#{@passenger_root}/ext/nginx"
  end


  def test_cmd
    ds = @nginx.app.server_apps.first.shell
    ds.set_mock_response 0, "passenger-config --root" => [:out, @passenger_root]

    @nginx.start
    @nginx.stop

    assert_ssh_call start_cmd(@passenger)
    assert_ssh_call stop_cmd(@passenger)
  end


  def test_custom_sudo_cmd
    ds = @nginx.app.server_apps.first.shell
    ds.set_mock_response 0, "passenger-config --root" => [:out, @passenger_root]

    @nginx.sudo = "someuser"

    @nginx.start
    @nginx.stop

    assert_ssh_call start_cmd(@passenger), ds, :sudo => @nginx.sudo
    assert_ssh_call stop_cmd(@passenger), ds, :sudo => @nginx.sudo
  end


  def test_sudo_cmd
    ds = @passenger.app.server_apps.first.shell
    ds.set_mock_response 0, "gem list passenger -d" => [:out, @gemout]

    @passenger.start
    @passenger.stop

    assert_equal true, @passenger.sudo
    assert_ssh_call start_cmd(@passenger), ds, :sudo => true
    assert_ssh_call stop_cmd(@passenger), ds, :sudo => true
  end


  def test_setup_passenger
    ds = @passenger.app.server_apps.first.shell

    ds.set_mock_response 0, "passenger-config --root" => [:out, @passenger_root]
    ds.set_mock_response 0, "nginx -V 2>&1" => [:out, @nginx_passenger_check]

    @passenger.setup do |ds, binder|
      assert binder.sudo
      assert binder.use_passenger?
      assert_equal "/Library/Ruby/Gems/1.8/gems/passenger-2.2.11",
        binder.passenger_root
    end
  end


  def test_setup
    ds = @nginx.app.server_apps.first.shell
    ds.set_mock_response 0, "passenger-config --root" => [:out, @passenger_root]

    @nginx.setup do |ds, binder|
      assert !binder.sudo
      assert !binder.use_passenger?
      assert_equal "/Library/Ruby/Gems/1.8/gems/passenger-2.2.11",
        binder.passenger_root
    end
  end


  ## Helper methods

  def start_cmd svr
    svr.exit_on_failure "#{svr.bin} -c #{svr.config_file_path}", 10,
      "Could not start #{svr.name} for #{svr.app.name}"
  end


  def stop_cmd svr
    cmd = "test -f #{svr.pid} && kill -#{svr.sigkill} $(cat #{svr.pid}) && "+
            "sleep 1 && rm -f #{svr.pid}"

    svr.exit_on_failure cmd, 11,
      "Could not kill #{svr.name} pid for #{svr.app.name}"
  end
end
