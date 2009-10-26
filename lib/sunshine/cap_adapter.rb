module Sunshine

  class CapAdapter

    attr_reader :cap_instance
    attr_reader :project_repo, :deploy_path, :server_user, :env_vars

    def initialize(cap)
      @cap_instance = cap
    end

    def upload_file(local_dir, remote_dir)
    end

    def run_cmd(string)
    end

    def update_current_codebase
    end

    def revert_current_codebase
    end

    private

    def pull_repo
    end

  end

end
