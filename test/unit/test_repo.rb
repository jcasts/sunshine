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


  def test_attributes
    @repo.mock :update_repo_info

    %w{revision committer branch date message}.each do |attrib|
      @repo.send(attrib.to_sym)
    end

    assert_equal 5, @repo.method_call_count(:update_repo_info)
  end


  def test_update_repo_info
    begin
      Sunshine::Repo.new(@svn_url).update_repo_info
      raise "Didn't raise RepoError when it should have"
    rescue Sunshine::RepoError => e
      msg = "The 'update_repo_info' method must be implemented by child classes"
      assert_equal msg, e.message
    end
  end


  def test_checkout_to
    begin
      Sunshine::Repo.new(@svn_url).checkout_to mock_deploy_server, "somepath"
      raise "Didn't raise RepoError on checkout_cmd"
    rescue Sunshine::RepoError => e
      msg = "The 'checkout_cmd' method must be implemented by child classes"
      assert_equal msg, e.message
    end
  end
end
