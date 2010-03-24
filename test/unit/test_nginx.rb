require 'test/test_helper'

class TestNginx < Test::Unit::TestCase

  def setup
    @app = Sunshine::App.new TEST_APP_CONFIG_FILE
    @app.server_apps.first.extend MockOpen4
    @app.server_apps.first.shell.extend MockOpen4
    use_remote_shell @app.server_apps.first.shell

    @passenger = Sunshine::Nginx.new @app
    @nginx = Sunshine::Nginx.new @app, :port => 5000, :point_to => @passenger
    @gemout = <<-STR

*** LOCAL GEMS ***

passenger (2.2.4)
    Author: Phusion - http://www.phusion.nl/
    Rubyforge: http://rubyforge.org/projects/passenger
    Homepage: http://www.modrails.com/
    Installed at: /Library/Ruby/Gems/1.8

    Apache module for Ruby on Rails support.
    STR

    @nginx_passenger_check =
      "/opt/ruby-ypc/lib/ruby/gems/1.8/gems/passenger-2.2.11/ext/nginx"
  end


  def test_cmd
    ds = @nginx.app.server_apps.first.shell
    ds.set_mock_response 0, "gem list passenger -d" => [:out, @gemout]

    @nginx.start
    @nginx.stop

    assert_ssh_call start_cmd(@passenger)
    assert_ssh_call stop_cmd(@passenger)
  end


  def test_custom_sudo_cmd
    ds = @nginx.app.server_apps.first.shell
    ds.set_mock_response 0, "gem list passenger -d" => [:out, @gemout]

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

    ds.set_mock_response 0,
      "gem list passenger -d" => [:out, @gemout],
      "nginx -V 2>&1" => [:out, @nginx_passenger_check]

    @passenger.setup do |ds, binder|
      assert binder.sudo
      assert binder.use_passenger?
      assert_equal "/Library/Ruby/Gems/1.8/gems/passenger-2.2.4",
        binder.passenger_root
    end
  end


  def test_setup
    ds = @nginx.app.server_apps.first.shell
    ds.set_mock_response 0, "gem list passenger -d" => [:out, @gemout]

    @nginx.setup do |ds, binder|
      assert !binder.sudo
      assert !binder.use_passenger?
      assert_equal "/Library/Ruby/Gems/1.8/gems/passenger-2.2.4",
        binder.passenger_root
    end
  end


  ## Helper methods

  def start_cmd svr
    "#{svr.bin} -c #{svr.config_file_path}"
  end


  def stop_cmd svr
    "test -f #{svr.pid} && kill -#{svr.sigkill} $(cat #{svr.pid}) && "+
      "sleep 1 && rm -f #{svr.pid} || "+
      "echo 'No #{svr.name} process to stop for #{svr.app.name}';"
  end
end
