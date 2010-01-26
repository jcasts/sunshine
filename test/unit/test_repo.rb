require 'test/test_helper'

class TestRepo < Test::Unit::TestCase

  def setup
    @repo = Sunshine::Repo.new_of_type(:svn, "https://svnurl").extend MockObject
  end

  def test_new_of_type
    repo = Sunshine::Repo.new_of_type :svn, "https://svnurl"
    assert_equal Sunshine::SvnRepo, repo.class
    assert_equal "https://svnurl", repo.url

    repo = Sunshine::Repo.new_of_type "", "someurl"
    assert_equal Sunshine::Repo, repo.class
  end


  def test_attributes
    @repo.mock :update_repo_info

    %w{revision committer branch date message}.each do |attrib|
      @repo.send(attrib.to_sym)
    end

    assert_equal 5, @repo.method_call_count(:update_repo_info)
  end


  def test_update_repo_info
    begin
      Sunshine::Repo.new("repourl").update_repo_info
      raise "Didn't raise RepoError when it should have"
    rescue Sunshine::RepoError => e
      msg = "The 'update_repo_info' method must be implemented by child classes"
      assert_equal msg, e.message
    end
  end


  def test_checkout_to
    begin
      Sunshine::Repo.new("repourl").checkout_to "server_obj", "somepath"
      raise "Didn't raise RepoError on checkout_to"
    rescue Sunshine::RepoError => e
      msg = "The 'checkout_to' method must be implemented by child classes"
      assert_equal msg, e.message
    end
  end
end
