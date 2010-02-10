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
      ":refs: %d",
      ":tree: %t"
    ].join("%n")


    def initialize url, options={}
      super
      @tree = options[:tree] || "master"
    end


    def get_repo_info deploy_server, path
      info = YAML.load git_log(deploy_server, path)

      info[:date]   = Time.parse response[:date]
      info[:branch] = parse_branch response

      info
    rescue => e
      raise RepoError, e
    end


    def checkout_cmd path
      "git clone #{@url} #{scm_flags} . && git checkout #{@tree}"
    end


    def git_log deploy_server, dir
      git_options = "-1 --no-color --format=\"#{LOG_FORMAT}\""
      deploy_server.call "cd #{dir} && git log #{git_options}"
    end


    private

    def parse_branch response
      refs = response[:refs]
      return response[:tree] unless refs && !refs.strip.empty?

      ref_names = refs.delete('()').gsub('/', '_')
      ref_names.split(',').last.strip
    end
  end
end
