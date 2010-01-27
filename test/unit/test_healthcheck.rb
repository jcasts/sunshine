require 'test/test_helper'

class TestHealthcheck < Test::Unit::TestCase

  def setup
    @deploy_server = mock_deploy_server
    @health = Sunshine::Healthcheck.new "somepath", @deploy_server

    @test_disabled = "test -f #{@health.disabled_file}"
    @test_enabled  = "test -f #{@health.enabled_file}"
  end


  def test_initialize
    assert_equal [@deploy_server], @health.deploy_servers
    assert_equal "somepath/health.txt", @health.enabled_file
    assert_equal "somepath/health.disabled", @health.disabled_file
  end


  def test_disable
    @health.disable

    cmd = "touch #{@health.disabled_file} && rm -f #{@health.enabled_file}"
    assert_ssh_call cmd
  end


  def test_enable
    @health.enable

    cmd = "rm -f #{@health.disabled_file} && touch #{@health.enabled_file}"
    assert_ssh_call cmd
  end


  def test_remove
    @health.remove

    cmd = "rm -f #{@health.disabled_file} #{@health.enabled_file}"
    assert_ssh_call cmd
  end


  def test_status_down
    @deploy_server.set_mock_response 1,
      @test_disabled => [:err, ""],
      @test_enabled  => [:err, ""]

    assert_equal({@deploy_server.host => :down}, @health.status)

    assert_ssh_call @test_disabled
    assert_ssh_call @test_enabled
  end


  def test_status_ok
    @deploy_server.set_mock_response 1, @test_disabled => [:err, ""]
    @deploy_server.set_mock_response 0, @test_enabled  => [:out, ""]

    assert_equal({@deploy_server.host => :ok}, @health.status)
  end


  def test_status_disabled
    @deploy_server.set_mock_response 0, @test_disabled => [:out, ""]

    assert_equal({@deploy_server.host => :disabled}, @health.status)
  end
end
