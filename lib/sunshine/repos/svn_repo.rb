module Sunshine

  ##
  # Simple scm wrapper for subversion control.

  class SvnRepo < Repo

    ##
    # Check if this is an svn repo

    def self.valid? path="."
       git_svn?(path) || File.exist?(File.join(path, ".svn"))
    end


    ##
    # Get the repo info from the path to a checked out svn repo

    def self.get_info path=".", shell=nil
      shell ||= Sunshine.shell

      svn_url  = get_svn_url path, shell
      response = svn_log svn_url, shell

      info = {}

      info[:url]       = svn_url
      info[:revision]  = response.match(/revision="(.*)">/)[1]
      info[:committer] = response.match(/<author>(.*)<\/author>/)[1]
      info[:date]      = Time.parse response.match(/<date>(.*)<\/date>/)[1]
      info[:message]   = response.match(/<msg>(.*)<\/msg>/m)[1]
      info[:branch]    = svn_url.split("/").last

      info
    rescue => e
      raise RepoError, e
    end


    ##
    # Returns the svn logs as xml.

    def self.svn_log path, shell
      shell.call "svn log #{path} --limit 1 --xml"
    end


    ##
    # Check if this is a git-svn repo.

    def self.git_svn? path="."
      File.exist? File.join(path, ".git/svn")
    end


    ##
    # Get the svn url from a svn or git-svn checkout.

    def self.get_svn_url path, shell
      cmd = git_svn?(path) ? "git svn" : "svn"
      shell.call("cd #{path} && #{cmd} info | grep ^URL:").split(" ")[1]
    end


    def do_checkout path, shell
      shell.call "svn checkout #{scm_flags} #{@url} #{path}"
    end


    NAME_MATCH = /([^\/]+\/)+([^\/]+)\/(trunk|branches|tags)/

    def name
      @url.match(NAME_MATCH)[2]
    rescue
      raise RepoError, "SVN url must match #{NAME_MATCH.inspect}"
    end
  end
end
