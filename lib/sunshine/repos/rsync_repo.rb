module Sunshine

  ##
  # Allows uploading code directly using rsync, instead of a scm.

  class RsyncRepo < Repo

    def get_repo_info deploy_server, path
      {:flags => @flags}
    end


    def do_checkout deploy_server, path
      deploy_server.upload @url, path
    end
  end
end

