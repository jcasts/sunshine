module Sunshine

  ##
  # Simple scm wrapper for subversion control.

  class SvnRepo < Repo

    def update_repo_info
      response   = Sunshine.console.call "svn log #{@url} --limit 1 --xml"
      @revision  = response.match(/revision="(.*)">/)[1]
      @committer = response.match(/<author>(.*)<\/author>/)[1]
      @date      = Time.parse response.match(/<date>(.*)<\/date>/)[1]
      @message   = response.match(/<msg>(.*)<\/msg>/m)[1]
      @branch    = @url.split("/").last
      true
    rescue => e
      raise RepoError, e
    end


    def checkout_cmd path
      "svn checkout -r #{revision} #{url} #{path}"
    end
  end
end
