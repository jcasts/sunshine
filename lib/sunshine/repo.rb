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
    # Creates a new repo subclass object:
    #   Repo.new_of_type :svn, "https://path/to/repo/tags/releasetag"
    #   Repo.new_of_type :git, "user@gitbox.com:repo/path"

    def self.new_of_type repo_type, url, options={}
      repo = "#{repo_type.to_s.capitalize}Repo"
      Sunshine.const_get(repo).new(url, options)
    end


    ##
    # Looks for .git and .svn directories and determines if the passed path
    # is a recognized repo. Does not check for RsyncRepo since it's a
    # special case. Returns the appropriate repo object:
    #   Repo.detect "path/to/svn/repo/dir"
    #     #=> <SvnRepo @url="svn://url/of/checked/out/repo">
    #   Repo.detect "path/to/git/repo/dir"
    #     #=> <GitRepo, @url="git://url/of/git/repo", @branch="master">
    #   Repo.detect "invalid/repo/path"
    #     #=> nil

    def self.detect path=".", console=nil

      if SvnRepo.valid? path, console
        info = SvnRepo.get_info path, console
        SvnRepo.new info[:url], info

      elsif GitRepo.valid? path, console
        info = GitRepo.get_info path, console
        GitRepo.new info[:url], info
      end
    end


    ##
    # Gets repo information for the specified dir - Implemented by subclass

    def self.get_info path=".", console=nil
      raise RepoError,
        "The 'get_info' method must be implemented by child classes"
    end


    attr_reader :url

    def initialize url, options={}
      @scm = self.class.name.split("::").last.sub('Repo', '').downcase

      @url   = url
      @flags = [*options[:flags]].compact
    end


    ##
    # Checkout code to a deploy_server and return an info log hash:
    #   repo.chekout_to server, "some/path"
    #   #=> {:revision => 123, :committer => 'someone', :date => time_obj ...}

    def checkout_to path, console=nil
      console ||= Sunshine.console

      Sunshine.logger.info @scm,
        "Checking out to #{console.host} #{path}" do

        dependency = Sunshine::Dependencies[@scm]
        dependency.install! :call => console if dependency

        console.call "test -d #{path} && rm -rf #{path} || echo false"
        console.call "mkdir -p #{path}"

        do_checkout   path, console
        get_repo_info path, console
      end
    end


    ##
    # Checkout the repo - implemented by subclass

    def do_checkout path, console
      raise RepoError,
        "The 'do_checkout' method must be implemented by child classes"
    end


    ##
    # Get the name of the specified repo - implemented by subclass

    def name
      raise RepoError,
        "The 'name' method must be implemented by child classes"
    end


    ##
    # Returns the set scm flags as a string

    def scm_flags
      @flags.join(" ")
    end


    ##
    # Returns the repo information as a hash.

    def get_repo_info path=".", console=nil
      defaults = {:type => @scm, :url => @url, :path => path}

      defaults.merge self.class.get_info(path, console)
    end
  end
end
