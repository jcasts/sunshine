require 'test/test_helper'

class TestServerCluster < Test::Unit::TestCase

  def setup
    @cluster =
      Sunshine::ServerCluster.new Sunshine::Unicorn, 3, mock_app, :port => 2000

    @cluster.each{|server| server.extend MockObject }
  end


  def test_initialize
    name = "someserver.3333"

    cluster =
      Sunshine::ServerCluster.new Sunshine::Thin, 3, mock_app,
      :port => 3000, :name => name

    assert_equal Sunshine::ServerCluster, cluster.class
    assert Array === cluster
    assert_equal 3, cluster.length

    cluster.each_with_index do |server, index|
      port = 3000 + index
      assert_equal Sunshine::Thin, server.class
      assert_equal port, server.port
      assert_equal "#{name}.#{port}", server.name
    end
  end


  def test_forwarded_methods
    [:has_setup?, :status, :setup, :start, :stop, :restart].each do |method|
      @cluster.each do |server|
        server.mock method, :return => true
      end

      @cluster.send method

      @cluster.each do |server|
        assert server.method_called?(method)
      end
    end
  end
end
