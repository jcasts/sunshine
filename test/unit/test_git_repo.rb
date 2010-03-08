require 'test/test_helper'

class TestGitRepo < Test::Unit::TestCase

  def test_name
    git = Sunshine::GitRepo.new "git://myrepo/project.git"
    assert_equal "project", git.name

    git = Sunshine::GitRepo.new "ssh://user@host.xz:456/path/to/project.git"
    assert_equal "project", git.name

    git = Sunshine::GitRepo.new "user@host.xz:~user/path/to/project.git"
    assert_equal "project", git.name
  end


  def test_invalid_name
    git = Sunshine::GitRepo.new "project.git"
    git.name
    raise "GitRepo didn't catch invalid naming scheme: #{git.url}"
  rescue => e
    assert_equal "Git url must match #{Sunshine::GitRepo::NAME_MATCH.inspect}",
      e.message
  end

end
