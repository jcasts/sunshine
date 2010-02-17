module Sunshine

  ##
  # Allows uploading code directly using rsync, instead of a scm.

  class RsyncRepo < Repo

    def self.get_info path=".", console=nil
      {:flags => scm_flags}
    end


    def do_checkout deploy_server, path
      deploy_server.upload @url, path
    end
  end
end

