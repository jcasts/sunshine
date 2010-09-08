require 'test/test_helper'

class TestApp < Test::Unit::TestCase

  def setup
    mock_remote_shell_popen4
    @svn_url = "svn://subversion/path/to/app_name/trunk"

    @config = {
      :name => "app_name",
      :remote_checkout => true,
      :repo => {:type => "svn", :url => @svn_url},
      :remote_shells => ["user@some_server.com",
        ["server2.com", {:roles => "web db"}]],
      :root_path => "/usr/local/my_user/app_name"}

    @app = Sunshine::App.new @config
    @app.each do |server_app|
      server_app.extend MockObject
      server_app.shell.extend MockObject
    end

    @tmpdir = File.join Dir.tmpdir, "test_sunshine_#{$$}"

    mock_svn_response @app.repo.url
  end

  def teardown
    FileUtils.rm_rf @tmpdir
  end


  def test_initialize_without_name
    app = Sunshine::App.new :repo => {:type => "svn", :url => @svn_url},
            :remote_shells => ["user@some_server.com"]

    assert_equal "app_name", app.name
  end


  def test_initialize_with_config_file
    app = Sunshine::App.new TEST_APP_CONFIG_FILE
    config = YAML.load_file(TEST_APP_CONFIG_FILE)[:default]
    assert_attributes_equal config, app
  end


  def test_initialize_with_file_object
    file = File.open TEST_APP_CONFIG_FILE
    app = Sunshine::App.new file
    config = YAML.load_file(TEST_APP_CONFIG_FILE)[:default]
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

    @app.deploy do |app|
      assert app.connected?

      yield_called = true
    end

    assert !@app.connected?

    setup_cmd =
     "test -d #{@app.checkout_path} && rm -rf #{@app.checkout_path}"+
     " || echo false"

    mkdir_cmd = "mkdir -p #{@app.checkout_path}"

    checkout_cmd = "svn checkout " +
      "#{@app.repo.scm_flags} #{@app.repo.url} #{@app.checkout_path}"

    run_results = [
      "mkdir -p #{@app.server_apps.first.directories.join(" ")}",
      setup_cmd,
      mkdir_cmd,
      checkout_cmd,
      "ln -sfT #{@app.checkout_path} #{@app.current_path}"
    ]


    @app.each do |server_app|
      use_remote_shell server_app.shell

      run_results.each_index do |i|
        assert_ssh_call run_results[i]
      end
    end

    assert yield_called
  end


  TEST_CONFIG = <<-STR
    :conf1:
      :common:     "conf1"
      :from_conf1: true
      :not_conf4:  "conf1"

    :conf2:
      :inherits:   :conf1
      :common:     "conf2"
      :from_conf2: true
      :not_conf4:  "conf2"

    :conf3:
      :common:     "conf3"
      :from_conf3: true
      :not_conf4:  "conf3"

    :conf4:
      :inherits:
        - :conf2
        - :conf3
      :common:     "conf4"
      :from_conf4: true
  STR

  def test_merge_config_inheritance
    all_configs = YAML.load TEST_CONFIG
    main_conf   = all_configs[:conf2]

    main_conf = @app.send(:merge_config_inheritance, main_conf, all_configs)

    assert main_conf[:from_conf1]
    assert_equal "conf2", main_conf[:common]
  end


  def test_multiple_merge_config_inheritance
    all_configs = YAML.load TEST_CONFIG
    main_conf   = all_configs[:conf4]

    main_conf = @app.send(:merge_config_inheritance, main_conf, all_configs)

    assert main_conf[:from_conf1]
    assert main_conf[:from_conf2]
    assert main_conf[:from_conf3]
    assert_equal "conf4", main_conf[:common]
    assert_equal "conf3", main_conf[:not_conf4]
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
      "ls -rc1 #{@app.deploys_path}" => [:out, "last_deploy_dir"]

    @app.revert!

    @app.each do |sa|
      use_remote_shell sa.shell

      assert_ssh_call "rm -rf #{@app.checkout_path}"

      assert_ssh_call "ls -rc1 #{@app.deploys_path}"

      last_deploy =  "#{@app.deploys_path}/last_deploy_dir"
      assert_ssh_call "ln -sfT #{last_deploy} #{@app.current_path}"
    end
  end


  def test_build_control_scripts
    scripts_list = %w{start stop restart custom env}

    @app.server_apps.each do |sa|
      sa.shell.mock :file?, :return => false
    end

    @app.add_to_script :start,  "start script"
    @app.add_to_script :stop,   "stop script"
    @app.add_to_script :custom, "custom script"

    @app.build_control_scripts

    each_remote_shell do |ds|

      scripts_list.each do |script|
        assert_rsync(/#{script}/, "#{ds.host}:#{@app.scripts_path}/#{script}")
      end
    end
  end


  def test_build_deploy_info_file
    @app.build_deploy_info_file

    each_remote_shell do |ds|
      assert_rsync(/info/, "#{ds.host}:#{@app.scripts_path}/info")
    end
  end


  def test_build_erb
    erb_file = File.join(@tmpdir, "tmp.erb")

    FileUtils.mkdir_p @tmpdir
    File.open(erb_file, "w+") do |f|
      f.write "<%= name %>"
    end

    name = "test name"

    local_name = @app.build_erb(erb_file, binding)
    app_name = @app.build_erb(erb_file)

    assert_equal name, local_name
    assert_equal @app.name, app_name
  end


  def test_call
    calls = 0

    @app.call "test call", :sudo => true do |type, data, inn|
      calls += 1
    end

    assert_equal calls, @app.server_apps.length

    args = ["test call", {:sudo => true}]

    @app.each do |server_app|
      assert server_app.shell.method_called?(:call, :args => args)
    end
  end


  def test_checkout_codebase
    @app.checkout_codebase

    each_remote_shell do |ds|
      path = @app.checkout_path
      setup_cmd = "test -d #{path} && rm -rf #{path} || echo false"

      url   = @app.repo.url
      flags = @app.repo.scm_flags
      checkout_cmd =
        "svn checkout #{flags} #{url} #{path}"

      assert_ssh_call setup_cmd
      assert_ssh_call checkout_cmd
    end
  end


  def test_deployed?
    set_mock_response_for @app, 0,
      "cat #{@app.current_path}/info" => [:out,
          "---\n:deploy_name: '#{@app.deploy_name}'"]

    deployed = @app.deployed?

    state = true
    @app.server_apps.each do |sa|
      assert sa.method_called?(:deployed?)

      set_mock_response_for sa.shell, 0,
        "cat #{@app.current_path}/info" => [:out,
            "---\n:deploy_name: '#{@app.deploy_name}'"]

      state = false unless sa.deployed?
    end

    assert_equal state, deployed
    assert deployed
  end


  def test_install_deps
    nginx_dep = Sunshine.dependencies.get 'nginx'
    ruby_dep  = Sunshine.dependencies.get 'ruby'

    yum_sudo = Sunshine::Yum.sudo

    check_nginx = "test \"$(yum list installed #{nginx_dep.pkg} | "+
      "grep -c #{nginx_dep.pkg})\" -ge 1"
    check_ruby = "test \"$(yum list installed #{ruby_dep.pkg} | "+
      "grep -c #{ruby_dep.pkg})\" -ge 1"

    set_mock_response_for @app, 1, "apt-get --version" => [:err, ""]
    set_mock_response_for @app, 0, "yum --version" => [:out, "1.0"]

    set_mock_response_for @app, 1,
      {check_nginx => [:err, ""],
       check_ruby  => [:err, ""]},
      {:sudo => yum_sudo}

    @app.install_deps 'ruby', nginx_dep


    each_remote_shell do |ds|
      [nginx_dep, ruby_dep].each do |dep|
        check =
          "test \"$(yum list installed #{dep.pkg} | grep -c #{dep.pkg})\" -ge 1"
        install = dep.instance_variable_get "@install"

        assert_ssh_call check, ds, :sudo => yum_sudo
        assert_ssh_call install, ds, :sudo => yum_sudo
      end
    end
  end


  def test_install_gem_deps
    rake_dep = Sunshine.dependencies.get 'rake'
    bundler_dep  = Sunshine.dependencies.get 'bundler'

    gem_sudo = Sunshine::Gem.sudo

    checks = {
      rake_dep    => "gem list #{rake_dep.pkg} -i --version '>=0.8'",
      bundler_dep => "gem list #{bundler_dep.pkg} -i --version '>=0.9'"
    }

    checks.values.each do |check|
      set_mock_response_for @app, 1, {check => [:err, ""]}, {:sudo => gem_sudo}
    end

    @app.install_deps 'rake', bundler_dep

    each_remote_shell do |ds|
      [rake_dep, bundler_dep].each do |dep|

        install = dep.instance_variable_get "@install"

        assert_ssh_call checks[dep], ds, :sudo => gem_sudo
        assert_ssh_call install, ds, :sudo => gem_sudo
      end
    end
  end


  def test_find_all
    app = Sunshine::App.new :repo => {:type => "svn", :url => @svn_url},
            :remote_shells => [
              "user@some_server.com",
              ["server2.com", {:roles => "web db"}]
            ]

    server_apps = app.server_apps

    assert_equal server_apps, app.find
    assert_equal server_apps, app.find({})
    assert_equal server_apps, app.find(:all)
    assert_equal server_apps, app.find(nil)
  end


  def test_find
    app = Sunshine::App.new :repo => {:type => "svn", :url => @svn_url},
            :remote_shells => [
              "user@some_server.com",
              ["server2.com", {:roles => "web db"}]
            ]

    server_apps = app.server_apps

    assert_equal server_apps, app.find(:role => :web)
    assert_equal server_apps, app.find(:role => :db)

    assert_equal [server_apps[0]], app.find(:role => :all)
    assert_equal [server_apps[0]], app.find(:role => :blarg)
    assert_equal [server_apps[0]], app.find(:user => 'user')
    assert_equal [server_apps[0]], app.find(:host => 'some_server.com')

    assert_equal [server_apps[1]], app.find(:host => 'server2.com')
  end


  def test_make_app_directories
    @app.make_app_directories

    each_remote_shell do |ds|
      assert_ssh_call "mkdir -p #{@app.server_apps.first.directories.join(" ")}"
    end
  end


  def test_rake
    @app.rake("test:task")

    each_remote_shell do |ds|
      assert_ssh_call "cd #{@app.checkout_path} && rake test:task"
    end
  end


  def test_register_as_deployed
    @app.register_as_deployed

    each_remote_shell do |ds|
      assert_ssh_call "test -d #{@app.root_path}"

      yml_list = {@app.name => @app.root_path}.to_yaml
      path     = ds.expand_path(Sunshine::APP_LIST_PATH)

      assert ds.method_called?(:make_file, :args => [path, yml_list])
    end
  end


  def test_remove_old_deploys
    returned_dirs = %w{old_deploy1 old_deploy2 old_deploy3 main_deploy}
    old_deploys = returned_dirs[0..-2].map{|d| "#{@app.deploys_path}/#{d}"}

    list_cmd = "ls -1 #{@app.deploys_path}"
    rm_cmd   = "rm -rf #{old_deploys.join(" ")}"

    set_mock_response_for @app, 0,
      list_cmd => [:out, returned_dirs.join("\n")]

    Sunshine.setup 'max_deploy_versions' => 1

    @app.remove_old_deploys

    each_remote_shell do |ds|
      assert_ssh_call list_cmd
      assert_ssh_call rm_cmd
    end
  end


  def test_run_post_user_lambdas
    lambdas_ran = 0
    count = 5

    count.times do
      @app.after_user_script do |app|
        lambdas_ran = lambdas_ran.next
      end
    end

    assert_equal 0, lambdas_ran

    @app.run_post_user_lambdas

    assert_equal count, lambdas_ran
  end


  def test_shell_env
    new_env = {
      "PATH"      => "/etc/lib:$PATH",
      "RACK_ENV"  => "test",
      "RAILS_ENV" => "test"
    }

    @app.shell_env new_env

    assert_equal new_env, @app.shell_env
  end


  def test_symlink_current_dir
    @app.symlink_current_dir

    each_remote_shell do |ds|
      assert_ssh_call "ln -sfT #{@app.checkout_path} #{@app.current_path}"
    end
  end


  def test_threaded_each_errors
    err_host = "some_server.com"
    finished = 0

    @app.threaded_each do |server_app|
      if server_app.shell.host == err_host
        raise Sunshine::CriticalDeployError, server_app.shell.host
      else
        finished = finished.next
      end
    end

    raise "Didn't raise threaded error when it should have"

  rescue Sunshine::CriticalDeployError => e
    host = @app.server_apps.first.shell.host

    assert_equal host, e.message
    assert_equal (@app.server_apps.length - 1), finished
  end


  def test_upload_tasks
    path = "/path/to/tasks"

    @app.upload_tasks 'common', 'tpkg',
      :host => 'some_server.com',
      :remote_path => path

    shell = @app.find(:host => 'some_server.com').first.shell

    use_remote_shell shell

    assert_ssh_call "mkdir -p /path/to/tasks"

    %w{common tpkg}.each do |task|
      from = "#{Sunshine::ROOT}/templates/tasks/#{task}.rake"
      to   = "#{shell.host}:#{path}/#{task}.rake"

      assert_rsync from, to
    end
  end


  def test_upload_tasks_simple
    @app.upload_tasks

    path  = "#{@app.checkout_path}/lib/tasks"

    tasks =
      Dir.glob("#{Sunshine::ROOT}/templates/tasks/*").map{|t| File.basename t}

    each_remote_shell do |ds|
      assert_ssh_call "mkdir -p #{path}"

      tasks.each do |task|
        from = "#{Sunshine::ROOT}/templates/tasks/#{task}"
        to   = "#{ds.host}:#{path}/#{task}"

        assert_rsync from, to
      end
    end
  end


  def test_with_filter
    app = Sunshine::App.new :repo => {:type => "svn", :url => @svn_url},
            :remote_shells => ["user@server1.com", "user@server2.com"]

    assert_equal 2, app.server_apps.length

    app.with_filter :host => 'server1.com' do |app|
      assert_equal 1, app.server_apps.length
      assert_equal 'server1.com', app.server_apps.first.shell.host
    end

    assert_equal 2, app.server_apps.length
  end


  def test_sudo_assignment
    @app.sudo = "someuser"

    @app.each do |server_app|
      assert_equal "someuser", server_app.shell.sudo
    end
  end


  private


  def assert_attributes_equal(attr_hash, app)
    assert_equal attr_hash[:name], app.name
    assert_equal attr_hash[:repo][:url], app.repo.url
    assert_equal attr_hash[:root_path], app.root_path

    attr_hash[:remote_shells].each_with_index do |server_def, i|
      shell = Sunshine::RemoteShell.new(*server_def)
      assert_equal shell, app.server_apps[i].shell
    end
  end

end
