require 'test/test_helper'

class TestBinder < Test::Unit::TestCase

  def setup
    @target = [1,2,3]
    @binder = Sunshine::Binder.new @target
  end

  def test_set
    @binder.set :blah, "somevalue"
    assert_equal "somevalue", @binder.blah
  end

  def test_forward
    @binder.forward :join, :length
    assert_equal @target.join(" "), @binder.join(" ")
    assert_equal @target.length, @binder.length
  end
end
