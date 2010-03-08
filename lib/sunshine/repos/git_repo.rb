module Sunshine

  ##
  # Simple wrapper for git repos. Constructor supports :tree option to
  # specify either a branch or tree-ish to checkout:
  #   git = GitRepo.new "git://mygitrepo.git", :tree => "tags/release001"

  class GitRepo < Repo

    LOG_FORMAT = [
      ":revision: %H",
      ":committer: %cn",
      ":date: %cd",
      ":message: %s",
      ":refs: '%d'",
      ":tree: %t"
    ].join("%n")


    ##
    # Check if this is an svn repo

    def self.valid? path="."
       File.exist? File.join(path, ".git")
    end


    ##
    # Get the repo info from the path to a checked out git repo

    def self.get_info path=".", console=nil
      console ||= Sunshine.console

      info = YAML.load git_log(path, console)

      info[:date]   = Time.parse info[:date]
      info[:branch] = parse_branch info
      info[:url]    = git_origin path, console

      info
    rescue => e
      raise RepoError, e
    end


    ##
    # Returns the git logs for a path, formatted as yaml.

    def self.git_log path, console
      git_options = "-1 --no-color --format=\"#{LOG_FORMAT}\""
      console.call "cd #{path} && git log #{git_options}"
    end


    ##
    # Returns the fetch origin of the current git repo. Returns the path to a
    # public git repo by default:
    #   GitRepo.git_origin "/some/path", Sunshine.console
    #     #=> "git://myrepo/path/to/repo.git"
    #   GitRepo.git_origin "/some/path", Sunshine.console, false
    #     #=> "user@myrepo:path/to/repo.git"

    def self.git_origin path, console, public_url=true
      get_origin_cmd = "cd #{path} && git remote -v | grep \\(fetch\\)"

      origin = console.call get_origin_cmd
      origin = origin.split(/\t|\s/)[1]

      origin = make_public_url origin if public_url

      origin
    end


    ##
    # Returns the git url for a public checkout

    def self.make_public_url git_url
      url, protocol = git_url.split("://").reverse
      url, user     = url.split("@").reverse

      url.gsub!(":", "/") if !protocol

      "git://#{url}"
    end


    attr_accessor :tree

    def initialize url, options={}
      super
      @tree = options[:branch] || options[:tree] || "master"
    end


    def do_checkout path, console
      cmd = "cd #{path} && git clone #{@url} #{scm_flags} . && "+
        "git checkout #{@tree}"
      console.call cmd
    end


    NAME_MATCH = /\/([^\/]+)\.git/

    def name
      @url.match(NAME_MATCH)[1]
    rescue
      raise RepoError, "Git url must match #{NAME_MATCH.inspect}"
    end


    private

    def self.parse_branch response
      refs = response[:refs]
      return response[:tree] unless refs && !refs.strip.empty?

      ref_names = refs.delete('()').gsub('/', '_')
      ref_names.split(',').last.strip
    end
  end
end
