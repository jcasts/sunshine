module Sunshine

  class RepoError < Exception; end

  class Repo

    include Open3

    def self.new_of_type(repo_type, url)
      repo_sym = "#{repo_type.capitalize}Repo".to_sym
      Sunshine.const_get(repo_sym).new(url)
    end

    attr_reader :url, :revision, :committer

    def initialize(url)
      @url = url
      update_repo_info
    end

    def update_repo_info
      raise RepoError, "The 'update_repo_info' method must be implemented by child classes"
    end

    def checkout_to(server, path)
      raise RepoError, "The 'checkout_to' method must be implemented by child classes"
    end

  end

end
