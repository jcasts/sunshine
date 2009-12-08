module Sunshine

  class RepoError < SunshineException; end

  class Repo

    ##
    # Creates a new repo subclass object
    def self.new_of_type(repo_type, url)
      repo = "#{repo_type.capitalize}Repo"
      Sunshine.const_get(repo).new(url)
    end

    attr_reader :url

    def initialize(url)
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
      raise RepoError, "The 'update_repo_info' method must be implemented by child classes"
    end

    ##
    # Checkout code to a deploy_server - Implemented by subclass
    def checkout_to(server, path)
      raise RepoError, "The 'checkout_to' method must be implemented by child classes"
    end

  end

end
