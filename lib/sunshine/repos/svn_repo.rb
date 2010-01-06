module Sunshine

  class SvnRepo < Repo

    def update_repo_info
      response = Sunshine.console.run("svn log #{@url} --limit 1 --xml")
      @revision = response.match(/revision="(.*)">/)[1]
      @committer = response.match(/<author>(.*)<\/author>/)[1]
      @date = Time.parse response.match(/<date>(.*)<\/date>/)[1]
      @message = response.match(/<msg>(.*)<\/msg>/m)[1]
      @branch = @url.split("/").last
      true
    rescue => e
      raise RepoError.new(e)
    end

    def checkout_to(deploy_server, path)
      Sunshine.logger.info :svn,
        "Checking out to #{deploy_server.host} #{path}" do
        Sunshine::Dependencies.install 'subversion', :call => deploy_server
        deploy_server.run "test -d #{path} && rm -rf #{path} || echo false"
        deploy_server.run \
          "mkdir -p #{path} && svn checkout -r #{@revision} #{@url} #{path}"
      end
    end

  end

end
