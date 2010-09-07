module Sunshine

  ##
  # Allows uploading code directly using rsync, instead of a scm.

  class RsyncRepo < Repo

    def self.get_info path=".", shell=nil
      {}
    end


    def self.valid?
      false
    end


    def initialize url, options={}
      super
      @flags << '-r' << '--exclude .svn/' << '--exclude .git/'
      @url << "/" unless @url[-1..-1] == "/"
    end


    def do_checkout path, shell
      shell.upload @url, path, :flags => @flags
    end


    def name
      File.basename @url
    end
  end
end

