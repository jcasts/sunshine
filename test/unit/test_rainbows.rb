require 'test/test_helper'
require 'test/unit/test_unicorn'

class TestRainbows < TestUnicorn

  def setup
    super
    @app.deploy_servers.each{|ds| ds.extend MockOpen4}
    @server = Sunshine::Rainbows.new @app
  end


  def test_setup
    @server.use_concurrency :model => :TreadSpawn, :timeout => 1
    @server.setup do |ds, binder|
      assert_equal @server.concurrency, binder.concurrency
    end
  end


  def test_use_concurrency
    concurrency = {:model => :ModelName, :timeout => 1, :connections => 500}
    @server.use_concurrency concurrency
    assert_equal concurrency, @server.concurrency
  end
end
