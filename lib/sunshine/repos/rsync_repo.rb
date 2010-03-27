module Sunshine

  ##
  # Allows uploading code directly using rsync, instead of a scm.

  class RsyncRepo < Repo

    def self.get_info path=".", shell=nil
      {}
    end


    def initialize url, options={}
      super
      @flags << "-r"
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

