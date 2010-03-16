require 'test/test_helper'

class TestRepo < Test::Unit::TestCase

  def setup
    @svn_url = "https://svnurl/to/repo/tag"
    @repo = Sunshine::Repo.new_of_type(:svn, @svn_url)
    @repo.extend MockObject
  end

  def test_new_of_type
    repo = Sunshine::Repo.new_of_type :svn, @svn_url
    assert_equal Sunshine::SvnRepo, repo.class
    assert_equal @svn_url, repo.url

    repo = Sunshine::Repo.new_of_type "", @svn_url
    assert_equal Sunshine::Repo, repo.class
  end


  def test_get_repo_info
    ds = mock_remote_shell
    begin
      Sunshine::Repo.new(@svn_url).get_repo_info ds, "path/to/repo"
      raise "Didn't raise RepoError when it should have"
    rescue Sunshine::RepoError => e
      msg = "The 'get_info' method must be implemented by child classes"
      assert_equal msg, e.message
    end
  end


  def test_checkout_to
    begin
      Sunshine::Repo.new(@svn_url).checkout_to "somepath", mock_remote_shell
      raise "Didn't raise RepoError on checkout_cmd"
    rescue Sunshine::RepoError => e
      msg = "The 'do_checkout' method must be implemented by child classes"
      assert_equal msg, e.message
    end
  end
end
