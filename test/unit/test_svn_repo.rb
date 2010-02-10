require 'test/test_helper'

class TestSvnRepo < Test::Unit::TestCase

  def setup
    @svn = Sunshine::SvnRepo.new("svn://someurl/somebranch")
    @ds = mock_deploy_server
    mock_svn_response @svn
  end

  def test_get_repo_info
    info = @svn.get_repo_info @ds, "path/to/checkout"

    assert_equal "786",        info[:revision]
    assert_equal "jcastagna",  info[:committer]
    assert_equal "somebranch", info[:branch]

    assert_equal "finished testing server.rb", info[:message]

    date = Time.parse "2010-01-26T01:49:17.372152Z"
    assert_equal date, info[:date]
  end

  def test_checkout_to
    path = "/test/checkout/path"

    @svn.checkout_to @ds, path

    assert_ssh_call "test -d #{path} && rm -rf #{path} || echo false"
    assert_ssh_call "mkdir -p #{path} && "+
      "svn checkout #{@svn.scm_flags} #{@svn.url} #{path}"
  end
end
