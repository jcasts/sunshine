require 'test/test_helper'

class TestDeployServerDispatcher < Test::Unit::TestCase

  def setup
    mock_deploy_server_popen4
    @dsd = Sunshine::DeployServerDispatcher.new "svr1.com", "svr2.com"
    @dsd.each{|ds| ds.extend MockObject}
  end

  def test_initialize
    dsd = Sunshine::DeployServerDispatcher.new "host1.com", "host2.com"

    assert Array === dsd
    assert_equal 2, dsd.length

    dsd.each do |ds|
      assert_equal Sunshine::DeployServer, ds.class
      assert dsd.exist?(ds)
    end
  end


  def test_append
    ds = Sunshine::DeployServer.new "svr1.com"
    @dsd << ds << "svr3.com"

    assert_equal 3, @dsd.length
  end


  def test_add
    @dsd.add "svr3.com", "svr4.com"

    assert_equal 4, @dsd.length
  end


  def test_add_nil
    assert_equal 2, @dsd.length
    @dsd.add nil, nil
    assert_equal 2, @dsd.length
  end


  def test_each
    servers = %w{svr1.com svr2.com}
    @dsd.each do |ds|
      servers.delete(ds.host)
    end

    assert_equal [], servers
  end


  def test_find
    @dsd << Sunshine::DeployServer.new("test1.com", :user => "bob")
    @dsd << Sunshine::DeployServer.new("test1.com", :roles => :web)
    @dsd << Sunshine::DeployServer.new("test2.com",
      :roles => :web, :user => "bob")

    assert_equal 2, @dsd.find(:role => :web).length
    assert_equal 2, @dsd.find(:user => "bob").length
    assert_equal 2, @dsd.find(:host => "test1.com").length
    assert_equal 1, @dsd.find(:role => :web, :user => "bob").length
  end

  def test_not_connected
    assert !@dsd.connected?

    assert_equal 1, @dsd[0].method_call_count(:connected?)
    assert_equal 0, @dsd[1].method_call_count(:connected?)
  end


  def test_connected
    @dsd.connect
    assert @dsd.connected?

    @dsd.each do |ds|
      assert_equal 2, ds.method_call_count(:connected?)
    end

    @dsd << "newserver.com"

    assert !@dsd.connected?
  end


  def test_forwarded_methods
    @dsd.connect
    @dsd.symlink "blah", "blarg"
    @dsd.upload "blah", "blarg"
    @dsd.make_file "file", "content"
    @dsd.call "something to run"
    @dsd.disconnect

    %w{connect disconnect symlink upload make_file call}.each do |method_name|
      method_name = method_name.to_sym

      @dsd.each do |ds|
        assert ds.method_called?(method_name)
      end
    end
  end
end
