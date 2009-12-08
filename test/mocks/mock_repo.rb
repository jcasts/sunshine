class MockRepo < Sunshine::Repo

  def update_repo_info
    @revision = "mock_rev"
    @committer = "mock_committer"
    @date = "mock_date"
    @message = "mock_message"
    @branch = "mock_branch"
    true
  end

  def checkout_to(deploy_server, path)
    Sunshine.logger.info :svn, "Checking out to #{deploy_server.host} #{path}" do
      deploy_server.run "test -d #{path} && rm -rf #{path}"
      deploy_server.run "mkdir -p #{path} && svn checkout -r #{@revision} #{@url} #{path}"
    end
  end


end

Sunshine.send(:remove_const, :SvnRepo)
Sunshine::SvnRepo = MockRepo
