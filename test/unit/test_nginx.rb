require 'test/test_helper'

class TestNginx < Test::Unit::TestCase

  def setup
    @app = Sunshine::App.new TEST_APP_CONFIG_FILE
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
  end


  def test_cmd
    assert_equal start_cmd(@nginx), @nginx.start_cmd
    assert_equal stop_cmd(@nginx), @nginx.stop_cmd
  end


  def test_sudo_cmd
    assert_equal start_cmd(@passenger, true), @passenger.start_cmd
    assert_equal stop_cmd(@passenger, true), @passenger.stop_cmd
  end


  def test_setup_passenger
    ds = @passenger.deploy_servers.first.extend MockOpen4
    ds.set_mock_response 0, "gem list passenger -d" => [:out, @gemout]

    @passenger.setup do |ds, binder|
      assert binder.run_sudo?
      assert binder.use_passenger?
      assert_equal "/Library/Ruby/Gems/1.8/gems/passenger-2.2.4",
        binder.passenger_root
    end
  end


  def test_setup
    ds = @nginx.deploy_servers.first.extend MockOpen4
    ds.set_mock_response 0, "gem list passenger -d" => [:out, @gemout]

    @nginx.setup do |ds, binder|
      assert !binder.run_sudo?
      assert !binder.use_passenger?
      assert_equal nil, binder.passenger_root
    end
  end


  ## Helper methods

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
