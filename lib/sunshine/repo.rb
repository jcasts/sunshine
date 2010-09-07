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
    # Adds subclasses to a repo_types hash for easy

    def self.inherited subclass
      @@repo_types ||= {}

      # Turn Sunshine::ScmNameRepo into :scm_name
      class_key = subclass.to_s.split("::").last
      class_key = $1 if class_key =~ /(\w+)Repo$/
      class_key.gsub!(/([a-z0-9])([A-Z])/, '\1_\2')
      class_key = class_key.downcase

      @@repo_types[class_key] = subclass
    end


    ##
    # Creates a new repo subclass object:
    #   Repo.new_of_type :svn, "https://path/to/repo/tags/releasetag"
    #   Repo.new_of_type :git, "user@gitbox.com:repo/path"

    def self.new_of_type repo_type, url, options={}
      repo_class = @@repo_types[repo_type.to_s]

      raise RepoError, "Invalid type #{repo_type.inspect}" unless repo_class

      repo_class.new(url, options)
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

    def self.detect path=".", shell=nil
      @@repo_types.values.each do |repo|
        next if Sunshine::RsyncRepo === repo

        if repo.valid? path
          info = repo.get_info path, shell
          return repo.new(info[:url], info)
        end
      end

      nil
    end


    ##
    # Gets repo information for the specified dir - Implemented by subclass

    def self.get_info path=".", shell=nil
      raise RepoError,
        "The 'get_info' method must be implemented by child classes"
    end


    ##
    # Checks if current working directory is a valid repo.
    # Defaults to false. Subclasses must override this method to enable
    # auto detecting of a given scm implementation.

    def self.valid?
      false
    end


    attr_reader :url, :scm

    def initialize url, options={}
      @scm = self.class.name.split("::").last.sub('Repo', '').downcase

      @url   = url.to_s
      @flags = [*options[:flags]].compact
    end


    ##
    # Checkout code to a shell and return an info log hash:
    #   repo.chekout_to "some/path", remote_shell
    #   #=> {:revision => 123, :committer => 'someone', :date => time_obj ...}

    def checkout_to path, shell=nil
      shell ||= Sunshine.shell

      shell.call "test -d #{path} && rm -rf #{path} || echo false"
      shell.call "mkdir -p #{path}"

      do_checkout   path, shell
      get_repo_info path, shell
    end


    ##
    # Checkout the repo - implemented by subclass

    def do_checkout path, shell
      raise RepoError,
        "The 'do_checkout' method must be implemented by child classes"
    end


    ##
    # Get the project name of the specified repo - implemented by subclass

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

    def get_repo_info path=".", shell=nil
      defaults = {:type => @scm, :url => @url, :path => path}

      defaults.merge self.class.get_info(path, shell)
    end
  end
end
