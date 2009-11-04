require 'test/test_helper'

class TestApp < Test::Unit::TestCase

  def setup
    @config = {:name => "parity",
               :repo => {:type => "svn", :url => "svn://subversion.flight.yellowpages.com/argo/parity/trunk"},
               :deploy_servers => ["nextgen@np5.wc1.yellowpages.com"],
               :deploy_path => "/usr/local/nextgen/parity"}
  end

  def teardown
  end

  def test_initialize_with_config_file
    app = Sunshine::App.new TEST_APP_CONFIG_FILE
    config = YAML.load_file(TEST_APP_CONFIG_FILE)[:defaults]
    assert_attributes_equal config, app
  end

  def test_initialize_with_options
    app = Sunshine::App.new @config
    assert_attributes_equal @config, app
  end

  def test_initialize_with_options_and_config_file
    app = Sunshine::App.new TEST_APP_CONFIG_FILE, @config
    assert_attributes_equal @config, app
  end

  def test_app_deploy
    yield_called = false

    Sunshine::DeployServer.class_eval do
      attr_reader :run_log
      def run(cmd)
        (@run_log ||= []) << cmd
      end
    end

    app = Sunshine::App.deploy @config do
      yield_called = true
    end

    run_results = []
    checkout_path = "#{app.deploy_path}/revisions/#{app.repo.revision}"
    run_results << "test -d #{checkout_path} && rm -rf #{checkout_path}"
    run_results << "mkdir #{checkout_path} && svn checkout -r #{app.repo.revision} #{app.repo.url} #{checkout_path}"
    run_results << "test -f #{app.checkout_path}/VERSION && rm #{app.checkout_path}/VERSION"
    run_results << "echo 'deployed_at: #{Time.now.to_i}\ndeployed_by: #{Sunshine.run_local("whoami")}\nscm_url: #{app.repo.url}\nscm_rev: #{app.repo.revision}' >> #{app.checkout_path}/VERSION"

    app.deploy_servers.each do |server|
      run_results.each_index do |i|
        assert_equal run_results[i], server.run_log[i]
      end
    end
    assert yield_called
  end


  private

  def assert_attributes_equal(attr_hash, app)
    assert_equal attr_hash[:name], app.name
    assert_equal attr_hash[:repo][:url], app.repo.url
    assert_equal attr_hash[:repo][:type], app.repo.class.name.split("::").last[0..-5].downcase
    assert_equal attr_hash[:deploy_path], app.deploy_path

    attr_hash[:deploy_servers].each_with_index do |server_def, i|
      user, url = server_def.split("@")
      assert_equal user, app.deploy_servers[i].user
      assert_equal url, app.deploy_servers[i].host
    end
  end

end
