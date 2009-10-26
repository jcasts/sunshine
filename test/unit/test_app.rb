require 'test/test_helper'

class TestApp < Test::Unit::TestCase

  def setup
    @config_file = "test/fixtures/app_configs/test_app.yml"
    @config = {:name => "test",
               :repo => "http://repo.com/test",
               :deploy_servers => ["test@s1.com","test@s2.com"],
               :deploy_path => "deploy/path/test"}
  end

  def teardown
  end

  def test_initialize_with_config_file
    app = Sunshine::App.new @config_file
    config = YAML.load_file(@config_file)[:defaults]
    assert_attributes_equal config, app
  end

  def test_initialize_with_options
    app = Sunshine::App.new @config
    assert_attributes_equal @config, app
  end

  def test_initialize_with_options_and_config_file
    app = Sunshine::App.new @config_file, @config
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

    %w{checkout_codebase healthcheck check_version}.each do |cmd_name|
      Sunshine::Commands.class_eval <<-STR
        def self.#{cmd_name}(opt)
          "#{cmd_name} command for \#{opt[:name]}"
        end
      STR
    end

    app = Sunshine::App.deploy @config do
      yield_called = true
    end

    run_results = %w{checkout_codebase healthcheck check_version}.map do |cmd|
       "#{cmd} command for #{@config[:name]}"
    end

    app.deploy_servers.each do |server|
      assert_equal run_results, server.run_log
    end
    assert yield_called
  end


  private

  def assert_attributes_equal(attr_hash, app)
    assert_equal attr_hash[:name], app.name
    assert_equal attr_hash[:repo], app.repo
    assert_equal attr_hash[:deploy_path], app.deploy_path

    attr_hash[:deploy_servers].each_with_index do |server_def, i|
      user, url = server_def.split("@")
      assert_equal user, app.deploy_servers[i].user
      assert_equal url, app.deploy_servers[i].url
    end
  end

end
