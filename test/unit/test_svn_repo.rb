require 'test/test_helper'

class TestSvnRepo < Test::Unit::TestCase

  def setup
    @svn = Sunshine::SvnRepo.new("svn://someurl/proj_name/somebranch")
    @ds = mock_deploy_server
    mock_svn_response @svn.url
  end

  def test_get_repo_info
    info = @svn.get_repo_info "path/to/checkout", @ds

    assert_equal "786",        info[:revision]
    assert_equal "jcastagna",  info[:committer]
    assert_equal "somebranch", info[:branch]

    assert_equal "finished testing server.rb", info[:message]

    date = Time.parse "2010-01-26T01:49:17.372152Z"
    assert_equal date, info[:date]
  end

  def test_checkout_to
    path = "/test/checkout/path"

    @svn.checkout_to path, @ds

    assert_ssh_call "test -d #{path} && rm -rf #{path} || echo false"
    assert_ssh_call "mkdir -p #{path}"
    assert_ssh_call "svn checkout #{@svn.scm_flags} #{@svn.url} #{path}"
  end


  def test_name
    svn = Sunshine::SvnRepo.new "svn://myrepo/project/trunk"
    assert_equal "project", svn.name

    svn = Sunshine::SvnRepo.new "svn://myrepo/project/branches/blah"
    assert_equal "project", svn.name

    svn = Sunshine::SvnRepo.new "svn://myrepo/project/tags/blah"
    assert_equal "project", svn.name
  end


  def test_invalid_name
    svn = Sunshine::SvnRepo.new "svn://myrepo/project"
    svn.name
    raise "SvnRepo didn't catch invalid naming scheme: #{svn.url}"
  rescue => e
    assert_equal "SVN url must match #{Sunshine::SvnRepo::NAME_MATCH.inspect}",
      e.message
  end
end
