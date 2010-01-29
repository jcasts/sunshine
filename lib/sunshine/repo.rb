module Sunshine

  class RepoError < Exception; end

  ##
  # An abstract class to wrap simple basic scm features. The primary function
  # of repo objects is to get information about the scm branch that is being
  # deployed and to check it out on remote deploy servers

  class Repo

    ##
    # Creates a new repo subclass object
    def self.new_of_type(repo_type, url)
      repo = "#{repo_type.to_s.capitalize}Repo"
      Sunshine.const_get(repo).new(url)
    end

    attr_reader :url

    def initialize url
      @name = self.class.name.split("::").last.sub('Repo', '').downcase
      @url = url
      @revision = nil
      @committer = nil
      @branch = nil
      @date = nil
      @message = nil
    end

    ##
    # Get the revision
    def revision
      update_repo_info unless @revision
      @revision
    end

    ##
    # Get the last committer
    def committer
      update_repo_info unless @committer
      @committer
    end

    ##
    # Get the current branch
    def branch
      update_repo_info unless @branch
      @branch
    end

    ##
    # Get the current date
    def date
      update_repo_info unless @date
      @date
    end

    ##
    # Get the current message
    def message
      update_repo_info unless @message
      @message
    end

    ##
    # Update the repo information - Implemented by subclass
    def update_repo_info
      raise RepoError,
        "The 'update_repo_info' method must be implemented by child classes"
    end

    ##
    # Checkout code to a deploy_server
    def checkout_to deploy_server, path
      Sunshine.logger.info @name,
        "Checking out to #{deploy_server.host} #{path}" do

        dependency = Sunshine::Dependencies[@name]
        dependency.install! :call => deploy_server if dependency

        deploy_server.call "test -d #{path} && rm -rf #{path} || echo false"
        deploy_server.call "mkdir -p #{path} && #{checkout_cmd(path)}"
      end
    end


    ##
    # Command to run to checkout the repo - implemented by subclass
    def checkout_cmd path
      raise RepoError,
        "The 'checkout_cmd' method must be implemented by child classes"
    end
  end
end
