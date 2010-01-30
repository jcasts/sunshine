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

    @tmpdir = File.join Dir.tmpdir, "test_sunshine_#{$$}"

    mock_svn_response @app.repo
  end

  def teardown
    FileUtils.rm_f @tmpdir
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

    app = Sunshine::App.deploy @config do |app|
      assert app.deploy_servers.connected?

      yield_called = true
    end

    assert !app.deploy_servers.connected?

    setup_cmd =
     "test -d #{app.checkout_path} && rm -rf #{app.checkout_path} || echo false"
    checkout_cmd = "mkdir -p #{app.checkout_path} && svn checkout -r " +
        "#{app.repo.revision} #{app.repo.url} #{app.checkout_path}"

    run_results = [
      "mkdir -p #{app.deploy_path}",
      setup_cmd,
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


  def test_build_control_scripts
    @app.scripts[:start]  << "start script"
    @app.scripts[:stop]   << "stop script"
    @app.scripts[:custom] << "custom script"

    @app.build_control_scripts

    each_deploy_server do |ds|

      %w{start stop restart custom}.each do |script|
        assert_rsync(/#{script}/, "#{ds.host}:#{@app.deploy_path}/#{script}")
        assert_ssh_call "chmod 0755 #{@app.deploy_path}/#{script}"
      end
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


  def test_checkout_codebase
    @app.checkout_codebase

    each_deploy_server do |ds|
      path = @app.checkout_path
      setup_cmd = "test -d #{path} && rm -rf #{path} || echo false"

      rev = @app.repo.revision
      url = @app.repo.url
      checkout_cmd =
        "mkdir -p #{path} && svn checkout -r #{rev} #{url} #{path}"

      assert_ssh_call setup_cmd
      assert_ssh_call checkout_cmd
    end
  end


  def test_install_deps
    nginx_dep = Sunshine::Dependencies['nginx']
    ruby_dep  = Sunshine::Dependencies['ruby']

    check_nginx = "test \"$(yum list installed #{nginx_dep.pkg} | "+
      "grep -c #{nginx_dep.pkg})\" -ge 1"
    check_ruby = "test \"$(yum list installed #{ruby_dep.pkg} | "+
      "grep -c #{ruby_dep.pkg})\" -ge 1"


    set_mock_response_for @app, 1,
      check_nginx => [:err, ""],
      check_ruby  => [:err, ""]

    @app.install_deps 'ruby', nginx_dep

    each_deploy_server do |ds|
      [nginx_dep, ruby_dep].each do |dep|
        check =
          "test \"$(yum list installed #{dep.pkg} | grep -c #{dep.pkg})\" -ge 1"
        install = dep.instance_variable_get "@install"

        assert_ssh_call check
        assert_ssh_call install
      end
    end
  end


  def test_install_gems
    @app.install_gems

    each_deploy_server do |ds|
      assert_ssh_call "test -f #{@app.checkout_path}/config/geminstaller.yml"
      assert_ssh_call "cd #{@app.checkout_path} && geminstaller -e"

      assert_ssh_call "test -f #{@app.checkout_path}/Gemfile"
      assert_ssh_call "cd #{@app.checkout_path} && gem bundle"
    end
  end


  def test_make_app_directory
    @app.make_app_directory

    each_deploy_server do |ds|
      assert_ssh_call "mkdir -p #{@app.deploy_path}"
    end
  end


  def test_make_deploy_info_file
    @app.make_deploy_info_file

    each_deploy_server do |ds|
      assert_rsync(/info/, "#{ds.host}:#{@app.deploy_path}/info")
    end
  end


  def test_rake
    @app.rake("test:task")

    each_deploy_server do |ds|
      assert_ssh_call "cd #{@app.checkout_path} && rake test:task"
    end
  end


  def test_register_as_deployed
    @app.register_as_deployed

    each_deploy_server do |ds|
      assert_ssh_call "test -d #{@app.deploy_path}"

      yml_list = {@app.name => @app.deploy_path}.to_yaml
      assert_ssh_call "echo '#{yml_list}' > #{Sunshine::APP_LIST_PATH}"
    end
  end


  def test_remove_old_deploys
    returned_dirs = %w{old_deploy1 old_deploy2 old_deploy3 main_deploy}
    old_deploys = returned_dirs[0..-2].map{|d| "#{@app.deploys_dir}/#{d}"}

    list_cmd = "ls -1 #{@app.deploys_dir}"
    rm_cmd   = "rm -rf #{old_deploys.join(" ")}"

    set_mock_response_for @app, 0,
      list_cmd => [:out, returned_dirs.join("\n")]

    Sunshine.setup 'max_deploy_versions' => 1

    @app.remove_old_deploys

    each_deploy_server do |ds|
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


  def test_setup_logrotate
    @app.crontab.extend MockObject

    config_path = "#{@app.checkout_path}/config"

    cronjob = "00 * * * * /usr/sbin/logrotate"+
      " --state /dev/null --force #{@app.current_path}/config/logrotate.conf"

    set_mock_response_for @app, 0,
      'crontab -l' => [:out, " "]

    @app.setup_logrotate

    assert @app.crontab.method_called?(:add, :args => "logrotate")
    assert @app.crontab.method_called?(:write!, :exactly => 1)

    new_crontab = @app.crontab.build

    assert_equal [cronjob], @app.crontab.jobs["logrotate"]

    each_deploy_server do |ds|
      assert_ssh_call "echo '#{new_crontab}' | crontab"
      assert_ssh_call "mkdir -p #{config_path} #{@app.log_path}/rotate"
      assert_rsync(/logrotate/, "#{ds.host}:#{config_path}/logrotate.conf")
    end
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

    each_deploy_server do |ds|
      assert_ssh_call "ln -sfT #{@app.checkout_path} #{@app.current_path}"
    end
  end


  def test_upload_tasks
    path = "/path/to/tasks"

    @app.upload_tasks 'common', 'tpkg',
      :servers => @app.deploy_servers,
      :path    => path

    each_deploy_server do |ds|
      assert_ssh_call "mkdir -p /path/to/tasks"

      %w{common tpkg}.each do |task|
        from = "templates/tasks/#{task}.rake"
        to   = "#{ds.host}:#{path}/#{task}.rake"

        assert_rsync from, to
      end
    end
  end


  def test_upload_tasks_simple
    @app.upload_tasks

    tasks = Dir.glob("templates/tasks/*").map{|t| File.basename t}
    path  = "#{@app.checkout_path}/lib/tasks"

    each_deploy_server do |ds|
      assert_ssh_call "mkdir -p #{path}"

      tasks.each do |task|
        from = "templates/tasks/#{task}"
        to   = "#{ds.host}:#{path}/#{task}"

        assert_rsync from, to
      end
    end
  end


  private

  def each_deploy_server app=@app
    app.deploy_servers.each do |ds|
      use_deploy_server ds
      yield(ds) if block_given?
    end
  end

  def assert_attributes_equal(attr_hash, app)
    assert_equal attr_hash[:name], app.name
    assert_equal attr_hash[:repo][:url], app.repo.url
    assert_equal attr_hash[:deploy_path], app.deploy_path

    attr_hash[:deploy_servers].each_with_index do |server_def, i|
      server_def = server_def.first if Array === server_def
      user, host = server_def.split("@")
      assert_equal host, app.deploy_servers[i].host
      assert_equal user, app.deploy_servers[i].user
    end
  end

end
