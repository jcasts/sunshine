module Sunshine

  ##
  # Simple scm wrapper for subversion control.

  class SvnRepo < Repo

    def get_repo_info deploy_server, path
      info     = {}
      response = svn_log deploy_server, path

      info[:revision]  = response.match(/revision="(.*)">/)[1]
      info[:committer] = response.match(/<author>(.*)<\/author>/)[1]
      info[:date]      = Time.parse response.match(/<date>(.*)<\/date>/)[1]
      info[:message]   = response.match(/<msg>(.*)<\/msg>/m)[1]
      info[:branch]    = @url.split("/").last

      info
    rescue => e
      raise RepoError, e
    end


    def do_checkout deploy_server, path
      deploy_server.call "svn checkout #{scm_flags} #{url} #{path}"
    end


    def svn_log deploy_server, dir
      deploy_server.call "svn log #{dir} --limit 1 --xml"
    end
  end
end
