module Sunshine

  class RepoError < Exception; end

  ##
  # An abstract class to wrap simple basic scm features. The primary function
  # of repo objects is to get information about the scm branch that is being
  # deployed and to check it out on remote deploy servers:
  #   svn = SvnRepo.new "svn://path/to/repo", :flags => "--ignore-externals"
  #
  # The :flags option can be a String or an Array and supports any scm
  # checkout (or clone for git) options.

  class Repo

    ##
    # Creates a new repo subclass object
    def self.new_of_type repo_type, url, options={}
      repo = "#{repo_type.to_s.capitalize}Repo"
      Sunshine.const_get(repo).new(url, options)
    end

    attr_reader :url

    def initialize url, options={}
      @name = self.class.name.split("::").last.sub('Repo', '').downcase

      @url   = url
      @flags = [*options[:flags]].compact
    end

    ##
    # Checkout code to a deploy_server and return an info log hash:
    #   repo.chekout_to server, "some/path"
    #   #=> {:revision => 123, :committer => 'someone', :date => time_obj ...}
    def checkout_to deploy_server, path
      Sunshine.logger.info @name,
        "Checking out to #{deploy_server.host} #{path}" do

        dependency = Sunshine::Dependencies[@name]
        dependency.install! :call => deploy_server if dependency

        deploy_server.call "test -d #{path} && rm -rf #{path} || echo false"
        deploy_server.call "mkdir -p #{path}"

        do_checkout deploy_server, path

        get_repo_info deploy_server, path
      end
    end

    ##
    # Returns the set scm flags as a string
    def scm_flags
      @flags.join(" ")
    end

    ##
    # Checkout the repo - implemented by subclass
    def do_checkout deploy_server, path
      raise RepoError,
        "The 'do_checkout' method must be implemented by child classes"
    end

    ##
    # Returns the repo information - Implemented by subclass
    def get_repo_info deploy_server, path
      raise RepoError,
        "The 'get_repo_info' method must be implemented by child classes"
    end
  end
end
