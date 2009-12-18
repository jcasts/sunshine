require 'test/test_helper'

class TestApp < Test::Unit::TestCase

  def setup
    svn_url = "svn://subversion.flight.yellowpages.com/argo/parity/trunk"

    @config = {:name => "parity",
               :repo => {:type => "svn", :url => svn_url},
               :deploy_servers => ["nextgen@np4.wc1.yellowpages.com"],
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
      undef run
      undef upload

      attr_reader :run_log
      def run(cmd)
        (@run_log ||= []) << cmd
        "some random stdout"
      end

      attr_reader :upload_log
      def upload(*args)
        (@upload_log ||= []) << args
      end
    end

    app = Sunshine::App.deploy @config do
      yield_called = true
    end

    run_results = []
    run_results << "mkdir -p #{app.deploy_path}"
    run_results << "test -d #{app.checkout_path} && rm -rf #{app.checkout_path}"
    run_results << "mkdir -p #{app.checkout_path} && svn checkout -r #{app.repo.revision} #{app.repo.url} #{app.checkout_path}"
    run_results << "ln -sfT #{app.checkout_path} #{app.current_path}"

    app.deploy_servers.each do |server|
      run_results.each_index do |i|
        assert_equal run_results[i], server.run_log[i]
      end
    end
    assert yield_called

  ensure
    Sunshine.send(:remove_const, :DeployServer)
    load 'sunshine/deploy_server.rb'
  end


  private

  def assert_attributes_equal(attr_hash, app)
    assert_equal attr_hash[:name], app.name
    assert_equal attr_hash[:repo][:url], app.repo.url
    # assert_equal attr_hash[:repo][:type], app.repo.class.name.split("::").last[0..-5].downcase
    assert_equal attr_hash[:deploy_path], app.deploy_path

    attr_hash[:deploy_servers].each_with_index do |server_def, i|
      server_def = server_def.keys.first if Hash === server_def
      user, url = server_def.split("@")
      assert_equal user, app.deploy_servers[i].user
      assert_equal url, app.deploy_servers[i].host
    end
  end

end
