module Sunshine

  ##
  # Allows uploading code directly using rsync, instead of a scm.

  class RsyncRepo < Repo

    def self.get_info path=".", console=nil
      {}
    end


    def initialize url, options={}
      super
      @flags << "-r"
    end


    def do_checkout deploy_server, path
      deploy_server.upload @url, path, :flags => @flags
    end
  end
end

