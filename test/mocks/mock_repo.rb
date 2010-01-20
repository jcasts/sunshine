module Sunshine
  class SvnRepo
    undef update_repo_info

    def update_repo_info
      @revision = "mock_rev"
      @committer = "mock_committer"
      @date = "mock_date"
      @message = "mock_message"
      @branch = "mock_branch"
      true
    end
  end
end
