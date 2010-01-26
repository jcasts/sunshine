require 'test/test_helper'

class TestServer < Test::Unit::TestCase

  class Server < Sunshine::Server
    def start_cmd
      "test start cmd"
    end

    def stop_cmd
      "test stop cmd"
    end
  end


  def setup
    mock_deploy_server_popen4
    @app    = Sunshine::App.new(TEST_APP_CONFIG_FILE).extend MockObject
    @deploy_server = @app.deploy_servers.first.extend MockObject
    @server = Server.new @app

    @rainbows = Sunshine::Rainbows.new(@app).extend MockObject
    use_deploy_server @deploy_server
  end


  def test_initialize
    assert_server_init

    config = {
      :point_to => @server,
      :pid      => "path/to/pid",
      :bin      => "path/to/bin",
      :port     => 1234,
      :processes => 10,
      :server_name => "serv1.com",
      :deploy_servers => ["deploy_server_test"],
      :config_template => "template.erb",
      :config_path => "path/to/config",
      :config_file => "conf_filename.conf",
      :log_path => "path/to/logs"
    }

    svr = Server.new @app, config

    config[:target] = config[:point_to]
    config[:stderr] = "#{config[:log_path]}/server_stderr.log"
    config[:stdout] = "#{config[:log_path]}/server_stdout.log"

    assert_server_init svr, config
  end


  def test_setup
    server = @rainbows

    server.setup do |ds|
      assert_equal @deploy_server, ds
    end

    args = ["rainbows", {:server => @deploy_server}]
    assert @app.method_called?(:install_deps, :args => args)

    assert server.method_called?(:upload_config_files)

    assert_ssh_call "gem list rainbows -i --version '0.6.0'"
    assert_ssh_call "mkdir -p #{server.send(:remote_dirs).join(" ")}"

    assert_rsync(/rainbows\.conf/, "jcast.np.wc1.yellowpages.com:"+
      "/usr/local/nextgen/envoy/current/server_configs/rainbows/rainbows.conf")
  end


  def test_start
    server = @rainbows

    server.start do |ds|
      assert_equal @deploy_server, ds
    end

    assert server.method_called?(:setup)

    assert_ssh_call server.start_cmd
  end


  def test_stop
    server = @rainbows

    server.stop do |ds|
      assert_equal @deploy_server, ds
    end

    assert_ssh_call server.stop_cmd
  end


  def test_restart
    server = @rainbows

    server.restart

    assert server.method_called?(:stop)
    assert server.method_called?(:start)
  end


  def test_restart_with_cmd
    server = @rainbows
    server.instance_variable_set("@restart_cmd", "RESTART!!1!")

    server.restart

    assert server.method_called?(:setup)
    assert_ssh_call server.restart_cmd
  end


  def test_missing_start_stop_cmd
    server = Sunshine::Server.new @app

    begin
      server.start_cmd
      raise "Should have thrown CriticalDeployError but didn't :("
    rescue Sunshine::CriticalDeployError => e
      assert_equal "@start_cmd undefined. Can't start server", e.message
    end

    begin
      server.stop_cmd
      raise "Should have thrown CriticalDeployError but didn't :("
    rescue Sunshine::CriticalDeployError => e
      assert_equal "@stop_cmd undefined. Can't stop server", e.message
    end
  end


  def test_log_files
    @server.log_files :test_log => "/path/test_log.log",
                      :another_test => "/path/another_test.log"

    assert_equal "/path/test_log.log", @server.log_file(:test_log)
    assert_equal "/path/another_test.log", @server.log_file(:another_test)
  end


  def test_upload_config_files
    server = @rainbows

    server.mock :config_template_files,
      :return => ["rainbows.conf.erb", "test/non_erb.conf"]

    @app.mock :build_erb, :return => "test_config"

    server.upload_config_files @deploy_server

    args = ["#{server.config_path}/rainbows.conf", "test_config"]
    assert @deploy_server.method_called?(:make_file, :args => args)

    args = ["test/non_erb.conf", "#{server.config_path}/non_erb.conf"]
    assert @deploy_server.method_called?(:upload, :args => args)
  end


  def test_config_template_files
    files = Dir["templates/rainbows/*"].select{|f| File.file?(f)}
    assert_equal files, @rainbows.config_template_files
  end


  def test_remote_dirs
    server = @rainbows

    dirs = server.send :remote_dirs

    assert_dir_in dirs, server.pid
    assert_dir_in dirs, server.config_file_path
    assert_dir_in dirs, server.log_file(:stderr)
    assert_dir_in dirs, server.log_file(:stdout)
  end


  def test_register_after_user_script
    server = @rainbows

    assert @app.method_called?(:after_user_script)

    @app.run_post_user_lambdas

    assert @app.scripts[:start].include?(server.start_cmd)
    assert @app.scripts[:stop].include?(server.stop_cmd)
    assert @app.scripts[:status].include?("test -f #{server.pid}")
    assert_equal server.port, @app.info[:ports][server.pid]
  end

  ##
  # Helper methods

  def assert_dir_in arr, file
    assert arr.include?(File.dirname(file))
  end


  def assert_server_init server=@server, user_config={}
    config = {
      :app => @app,
      :target => @app,
      :name => "server",
      :pid => "#{@app.shared_path}/pids/server.pid",
      :bin => "server",
      :port => 80,
      :processes => 1,
      :server_name => nil,
      :config_file => "server.conf",
      :config_path => "#{@app.current_path}/server_configs/server",
      :config_template => "templates/server/*",
      :deploy_servers => @app.deploy_servers.find(:role => :web),
      :stderr => "#{@app.log_path}/server_stderr.log",
      :stdout => "#{@app.log_path}/server_stdout.log"
    }.merge(user_config)

    assert_equal config[:app],         server.app
    assert_equal config[:bin],         server.bin
    assert_equal config[:pid],         server.pid
    assert_equal config[:port],        server.port
    assert_equal config[:name],        server.name
    assert_equal config[:target],      server.target
    assert_equal config[:processes],   server.processes
    assert_equal config[:server_name], server.server_name

    assert_equal config[:config_path],     server.config_path
    assert_equal config[:config_file],     server.config_file
    assert_equal config[:config_template], server.config_template


    assert_equal config[:stderr], server.log_file(:stderr)
    assert_equal config[:stdout], server.log_file(:stdout)

    assert_equal config[:deploy_servers], server.deploy_servers

    config_file_path = "#{config[:config_path]}/#{config[:config_file]}"
    assert_equal config_file_path, server.config_file_path
  end
end
