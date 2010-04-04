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
    mock_remote_shell_popen4
    @app    = Sunshine::App.new(TEST_APP_CONFIG_FILE).extend MockObject
    @server_app = @app.server_apps.first.extend MockObject
    @app.server_apps.first.shell.extend MockObject

    @server = Server.new @app

    @rainbows = Sunshine::Rainbows.new(@app).extend MockObject
    use_remote_shell @server_app.shell
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
      :server_apps => ["remote_shell_test"],
      :config_template => "template.erb",
      :config_path => "path/to/config",
      :config_file => "conf_filename.conf",
      :log_path => "path/to/logs",
      :sudo     => "sudouser"
    }

    svr = Server.new @app, config

    config[:target] = config[:point_to]
    config[:stderr] = "#{config[:log_path]}/server_stderr.log"
    config[:stdout] = "#{config[:log_path]}/server_stdout.log"

    assert_server_init svr, config
  end


  def test_setup
    server = @rainbows

    server.setup do |sa, binder|
      assert_equal @server_app, sa

      assert_equal sa.shell,      binder.shell
      assert_equal sa.shell.host, binder.server_name
      assert_equal @rainbows.send(:pick_sudo, sa.shell), binder.sudo
    end

    server.each_server_app do |sa|
      assert sa.method_called?(:install_deps, :args => ["rainbows"])

      assert server.method_called?(:configure_remote_dirs, :args => [sa.shell])
      assert server.method_called?(:touch_log_files, :args => [sa.shell])
      assert server.method_called?(:upload_config_files, :args => [sa.shell])
    end


    assert_rsync(/rainbows\.conf/, "some_server.com:"+
      "/usr/local/my_user/other_app/current/daemons/rainbows/rainbows.conf")

    assert server.has_setup?
  end


  def test_has_setup?
    server = @rainbows
    assert_equal nil, server.instance_variable_get("@setup_successful")

    @server_app.shell.mock :file?, :args => [server.config_file_path],
                                   :return => false

    assert_equal false, server.has_setup?

    @server_app.shell.mock :file?, :args => [server.config_file_path],
                                   :return => true

    assert_equal false, server.has_setup?
    assert_equal true,  server.has_setup?(true)
  end


  def test_new_cluster
    cluster = Sunshine::Server.new_cluster 3, @app, :port => 5000

    assert_equal Sunshine::ServerCluster, cluster.class
    assert Array === cluster
    assert_equal 3, cluster.length

    cluster.each_with_index do |server, index|
      port = 5000 + index
      assert_equal Sunshine::Server, server.class
      assert_equal port, server.port
      assert_equal "server.#{port}", server.name
    end
  end


  def test_start
    server = @rainbows
    @server_app.shell.mock :file?, :args => [server.config_file_path],
                                   :return => false

    server.start do |sa|
      assert_equal @server_app, sa
      assert_ssh_call server.start_cmd, sa.shell, :sudo => true
    end

    assert server.method_called?(:setup)
  end


  def test_start_missing_setup
    server = @rainbows
    @server_app.shell.mock :file?, :args => [server.config_file_path],
                                   :return => true

    server.start do |sa|
      assert_equal @server_app, sa
      assert_ssh_call server.start_cmd, sa.shell, :sudo => true
    end

    assert !server.method_called?(:setup)
  end


  def test_stop
    server = @rainbows

    server.stop do |sa|
      assert_equal @server_app, sa
      assert_ssh_call server.stop_cmd, sa.shell, :sudo => true
    end
  end


  def test_restart
    server = @rainbows

    server.restart do |sa|
      assert_equal @server_app, sa
      assert_ssh_call server.restart_cmd, sa.shell, :sudo => true
    end
  end


  def test_restart_missing_setup
    server = @rainbows
    @server_app.shell.mock :file?, :args => [server.config_file_path],
                                   :return => true

    server.restart
    assert !server.method_called?(:setup)
  end


  def test_restart_with_cmd
    server = @rainbows
    server.instance_variable_set("@restart_cmd", "RESTART!!1!")

    @server_app.shell.mock :file?, :args => [server.config_file_path],
                                   :return => false

    server.restart do |sa|
      assert_equal @server_app, sa
      assert_ssh_call server.restart_cmd, sa.shell, :sudo => true
    end

    assert server.method_called?(:setup)
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

    server.upload_config_files @server_app.shell

    args = ["#{server.config_path}/rainbows.conf", "test_config"]
    assert @server_app.shell.method_called?(:make_file, :args => args)

    args = ["test/non_erb.conf", "#{server.config_path}/non_erb.conf"]
    assert @server_app.shell.method_called?(:upload, :args => args)
  end


  def test_config_template_files
    files =
      Dir["#{Sunshine::ROOT}/templates/rainbows/*"].select{|f| File.file?(f)}
    assert_equal files, @rainbows.config_template_files
  end


  def test_register_after_user_script
    server = @rainbows

    assert @app.method_called?(:after_user_script) # called on Server#init

    @app.run_post_user_lambdas

    server.each_server_app do |sa|
      %w{start stop restart status}.each do |script|
        script_file = "#{server.config_path}/#{script}"
        cmd = sa.shell.sudo_cmd script_file, server.send(:pick_sudo, sa.shell)

        assert sa.scripts[script.to_sym].include?(cmd.join(" "))
      end

      assert_equal server.port, sa.info[:ports][server.pid]
    end
  end


  def test_pick_sudo
    ds = @rainbows.app.server_apps.first.shell
    assert_equal true, @rainbows.send(:pick_sudo, ds)

    @rainbows.sudo = true
    assert_equal true, @rainbows.send(:pick_sudo, ds)

    ds.sudo = true
    @rainbows.sudo = false
    assert_equal false, @rainbows.send(:pick_sudo, ds)

    ds.sudo = "blah"
    @rainbows.sudo = true
    assert_equal true, @rainbows.send(:pick_sudo, ds)

    @rainbows.sudo = "local"
    assert_equal "local", @rainbows.send(:pick_sudo, ds)
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
      :config_path => "#{@app.current_path}/daemons/server",
      :config_template => "#{Sunshine::ROOT}/templates/server/*",
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

    config_file_path = "#{config[:config_path]}/#{config[:config_file]}"
    assert_equal config_file_path, server.config_file_path
  end
end
