module Sunshine

  class SvnRepo < Repo

    def update_repo_info
      response = Sunshine.run_local("svn log #{@url} -l1 --xml")
      @revision = response.match(/revision="(.*)">/)[1]
      @committer = response.match(/<author>(.*)<\/author>/)[1]
      true
    end

    def checkout_to(server, path)
      server.run "test -d #{path} && rm -rf #{path}"
      server.run "mkdir #{path} && svn checkout -r #{@revision} #{@url} #{path}"
    end

  end

end
