module Sunshine

  class SvnRepo < Repo

    def update_repo_info
      response = Sunshine.run_local("svn log #{@url} --limit 1 --xml")
      @revision = response.match(/revision="(.*)">/)[1]
      @committer = response.match(/<author>(.*)<\/author>/)[1]
      true
    end

    def checkout_to(deploy_server, path)
      Sunshine.logger.info :svn, "Checking out to #{deploy_server.host} #{path}" do
        deploy_server.run "test -d #{path} && rm -rf #{path}"
        deploy_server.run "mkdir -p #{path} && svn checkout -r #{@revision} #{@url} #{path}"
      end
    end

  end

end
