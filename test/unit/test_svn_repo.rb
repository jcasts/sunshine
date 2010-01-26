require 'test/test_helper'

class TestSvnRepo < Test::Unit::TestCase

  def setup
    @svn = Sunshine::SvnRepo.new("svn://someurl/somebranch")
    mock_svn_response @svn
  end

  def test_update_repo_info
    assert_equal "786",        @svn.revision
    assert_equal "jcastagna",  @svn.committer
    assert_equal "somebranch", @svn.branch

    assert_equal "finished testing server.rb", @svn.message

    date = Time.parse "2010-01-26T01:49:17.372152Z"
    assert_equal date, @svn.date
  end

  def test_checkout_to
    ds = mock_deploy_server
    path = "/test/checkout/path"

    @svn.checkout_to ds, path

    assert_ssh_call "test -d #{path} && rm -rf #{path} || echo false"
    assert_ssh_call "mkdir -p #{path} && "+
      "svn checkout -r #{@svn.revision} #{@svn.url} #{path}"
  end
end
