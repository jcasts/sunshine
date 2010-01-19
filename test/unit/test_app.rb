require 'test/test_helper'

class TestApp < Test::Unit::TestCase

  def setup
    mock_deploy_server_popen4
    svn_url = "svn://subversion.flight.yellowpages.com/argo/parity/trunk"

    @config = {:name => "parity",
               :repo => {:type => "svn", :url => svn_url},
               :deploy_servers => ["jcastagna@jcast.np.wc1.yellowpages.com"],
               :deploy_path => "/usr/local/nextgen/parity"}

    @app = Sunshine::App.new @config
  end

  def teardown
  end


  def test_initialize_with_config_file
    app = Sunshine::App.new TEST_APP_CONFIG_FILE
    config = YAML.load_file(TEST_APP_CONFIG_FILE)[:defaults]
    assert_attributes_equal config, app
  end


  def test_initialize_with_options
    assert_attributes_equal @config, @app
  end


  def test_initialize_with_options_and_config_file
    app = Sunshine::App.new TEST_APP_CONFIG_FILE, @config
    assert_attributes_equal @config, app
  end


  def test_app_deploy
    yield_called = false

    app = Sunshine::App.deploy @config do |app|
      assert app.deploy_servers.connected?

      yield_called = true
    end

    assert !app.deploy_servers.connected?

    checkout_cmd = "mkdir -p #{app.checkout_path} && svn checkout -r " +
        "#{app.repo.revision} #{app.repo.url} #{app.checkout_path}"

    run_results = [
      "mkdir -p #{app.deploy_path}",
      "test -d #{app.checkout_path} && rm -rf #{app.checkout_path}",
      checkout_cmd,
      "ln -sfT #{app.checkout_path} #{app.current_path}"
    ]


    app.deploy_servers.each do |server|
      use_deploy_server server

      run_results.each_index do |i|
        assert_ssh_call run_results[i]
      end
    end

    assert yield_called
  end


  class MockError < Exception; end

  def test_app_deploy_error_handling
    [ MockError,
      Sunshine::CriticalDeployError,
      Sunshine::FatalDeployError ].each do |error|

      begin
        app = Sunshine::App.deploy @config do |app|
          raise error, "#{error} was not caught"
        end

      rescue MockError => e
        assert_equal MockError, e.class
      end
    end
  end


  def test_revert
    set_mock_response_for @app, 0,
      "ls -1 #{@app.deploys_dir}" => [:out, "last_deploy_dir"]

    @app.revert!

    @app.deploy_servers.each do |ds|
      use_deploy_server ds

      assert_ssh_call "rm -rf #{@app.checkout_path}"

      assert_ssh_call "ls -1 #{@app.deploys_dir}"

      last_deploy =  "#{@app.deploys_dir}/last_deploy_dir"
      assert_ssh_call "ln -sfT #{last_deploy} #{@app.current_path}"
    end
  end


  private

  def assert_attributes_equal(attr_hash, app)
    assert_equal attr_hash[:name], app.name
    assert_equal attr_hash[:repo][:url], app.repo.url
    assert_equal attr_hash[:deploy_path], app.deploy_path

    attr_hash[:deploy_servers].each_with_index do |server_def, i|
      server_def = server_def.keys.first if Hash === server_def
      user, host = server_def.split("@")
      assert_equal host, app.deploy_servers[i].host
      assert_equal user, app.deploy_servers[i].user
    end
  end

end
