require 'test_helper'

class TestServerApp < Test::Unit::TestCase

  def setup
    mock_svn_response

    @app = mock_app
    @app.repo.extend MockObject

    @sa = Sunshine::ServerApp.new @app, mock_remote_shell
    @sa.extend MockObject

    use_remote_shell @sa.shell
  end


  def test_init
    default_info = {:ports => {}}
    assert_equal default_info, @sa.info

    assert_equal @app, @sa.app
    assert_equal Hash.new, @sa.scripts
    assert_equal [:all], @sa.roles
  end


  def test_init_roles
    sa = Sunshine::ServerApp.new @app, "host", :roles => "role1 role2"
    assert_equal [:role1, :role2], sa.roles

    sa = Sunshine::ServerApp.new @app, "host", :roles => %w{role3 role4}
    assert_equal [:role3, :role4], sa.roles
  end


  def test_add_shell_paths
    @sa.add_shell_paths "test/path1", "test/path2"
    assert_equal "test/path1:test/path2:$PATH", @sa.shell_env['PATH']

    @sa.add_shell_paths "test/path3", "test/path4"
    assert_equal "test/path3:test/path4:test/path1:test/path2:$PATH",
      @sa.shell_env['PATH']
  end


  def test_app_attr
    sa_root_path   = "local/server_app/path"
    sa_deploy_name = "local_deploy_name"

    @sa = Sunshine::ServerApp.new "test", "host",
      :root_path => sa_root_path, :deploy_name => sa_deploy_name

    assert_equal sa_root_path,   @sa.root_path
    assert_equal sa_deploy_name, @sa.deploy_name
    assert_equal "test",         @sa.name

    @sa.app = @app

    assert_not_equal sa_root_path,   @sa.root_path
    assert_not_equal sa_deploy_name, @sa.deploy_name
    assert_not_equal "test",         @sa.name

    assert_equal @app.root_path,   @sa.root_path
    assert_equal @app.deploy_name, @sa.deploy_name
    assert_equal @app.name,        @sa.name
  end


  def test_build_control_scripts
    @sa.scripts[:start] << "start"
    @sa.scripts[:stop]  << "stop"
    @sa.scripts[:custom] << "custom"

    @sa.build_control_scripts

    [:start, :stop, :custom].each do |script|
      content = @sa.make_bash_script script, @sa.scripts[script]
      assert @sa.method_called?(:write_script, :args => [script, content])
    end

    content = @sa.make_env_bash_script
    assert @sa.method_called?(:write_script, :args => ["env", content])

    content = @sa.make_bash_script :restart,
      ["#{@sa.app.root_path}/stop", "#{@sa.app.root_path}/start"]
    assert @sa.method_called?(:write_script, :args => [:restart, content])
  end


  def test_build_deploy_info_file
    args = ["#{@app.checkout_path}/info", @sa.get_deploy_info.to_yaml]

    @sa.build_deploy_info_file

    assert @sa.shell.method_called?(:make_file, :args => args)

    args = ["#{@app.current_path}/info", "#{@app.root_path}/info"]

    assert @sa.shell.method_called?(:symlink, :args => args)
  end


  def test_checkout_repo
    @sa.checkout_repo @app.repo
    repo = @sa.app.repo
    args = [@app.checkout_path, @sa.shell]

    assert repo.method_called?(:checkout_to, :args => args)

    info = @app.repo.checkout_to @app.checkout_path, @sa.shell
    assert_equal info, @sa.info[:scm]
  end


  def test_deploy_details
    deploy_details = {:item => "thing"}
    other_details  = {:key  => "value"}

    @sa.shell.mock :call, :args   => ["cat #{@sa.current_path}/info"],
                          :return => other_details.to_yaml

    @sa.instance_variable_set "@deploy_details", deploy_details

    assert_equal deploy_details, @sa.deploy_details
    assert_equal other_details,  @sa.deploy_details(true)
  end


  def test_not_deployed?
    @sa.mock :deploy_details, :args   => [true],
                              :return => nil

    assert_equal false, @sa.deployed?
  end


  def test_server_checked_deployed?
    @sa.mock :deploy_details, :args   => [true],
                              :return => {:deploy_name => @sa.deploy_name}

    assert_equal true, @sa.deployed?
  end


  def test_cached_details_deployed?
    @sa.instance_variable_set "@deploy_details", :deploy_name => @sa.deploy_name

    assert_equal true, @sa.deployed?
  end


  def test_get_deploy_info
    test_info = {
      :deployed_at => Time.now.to_s,
      :deployed_as => @sa.shell.call("whoami"),
      :deployed_by => Sunshine.shell.user,
      :deploy_name => File.basename(@app.checkout_path),
      :roles       => @sa.roles,
      :path        => @app.root_path
    }.merge @sa.info

    deploy_info = @sa.get_deploy_info

    deploy_info.each do |key, val|
      next if key == :deployed_at
      assert_equal test_info[key], val
    end
  end


  def test_has_all_roles
    assert @sa.has_roles?([:web, :app, :blarg])
    assert @sa.has_roles?([:web, :app, :blarg], true)
  end


  def test_has_roles
    @sa.roles = [:web, :app]

    assert @sa.has_roles?(:web)
    assert @sa.has_roles?([:web, :app])

    assert !@sa.has_roles?([:blarg, :web, :app])
    assert @sa.has_roles?([:blarg, :web, :app], true)
  end


  def test_install_deps
    nginx_dep = Sunshine.dependencies.get 'nginx', :prefer => @sa.pkg_manager

    @sa.install_deps "ruby", nginx_dep

    assert_dep_install 'ruby'
    assert_dep_install 'nginx'
  end


  def test_install_deps_bad_type
    nginx_dep = Sunshine.dependencies.get 'nginx'

    @sa.install_deps nginx_dep, :type => Sunshine::Gem
    raise "Didn't raise missing dependency when it should have."

  rescue Sunshine::DependencyLib::MissingDependency => e
    assert_equal "No dependency 'nginx' [Sunshine::Gem]", e.message
  end


  def test_make_app_directories
    @sa.make_app_directories

    assert_server_call "mkdir -p #{@sa.directories.join(" ")}"
  end


  def test_make_bash_script
    app_script = @sa.make_bash_script "blah", [1,2,3,4]

    assert_bash_script "blah", [1,2,3,4], app_script
  end


  def test_make_env_bash_script
    @sa.shell.env = {"BLAH" => "blarg", "HOME" => "/home/blah"}

    test_script = "#!/bin/bash\nenv BLAH=blarg HOME=/home/blah \"$@\""

    assert_equal test_script, @sa.make_env_bash_script
  end


  def test_rake
    @sa.rake "db:migrate"

    assert_dep_install 'rake'
    assert_server_call "cd #{@app.checkout_path} && rake db:migrate"
  end


  def test_register_as_deployed
    Sunshine::AddCommand.extend MockObject unless
      MockObject === Sunshine::AddCommand

    @sa.register_as_deployed

    args = [@app.root_path, {'servers' => [@sa.shell]}]
    assert Sunshine::AddCommand.method_called?(:exec, :args => args)
  end


  def test_remove_old_deploys
    Sunshine.setup 'max_deploy_versions' => 3

    deploys = %w{ploy1 ploy2 ploy3 ploy4 ploy5}

    @sa.shell.mock :call,
      :args   => ["ls -1 #{@app.deploys_path}"],
      :return => "#{deploys.join("\n")}\n"

    removed = deploys[0..1].map{|d| "#{@app.deploys_path}/#{d}"}

    @sa.remove_old_deploys

    assert_server_call "rm -rf #{removed.join(" ")}"
  end


  def test_remove_old_deploys_unnecessary
    Sunshine.setup 'max_deploy_versions' => 5

    deploys = %w{ploy1 ploy2 ploy3 ploy4 ploy5}

    @sa.mock :call,
      :args   => ["ls -1 #{@app.deploys_path}"],
      :return => "#{deploys.join("\n")}\n"

    removed = deploys[0..1].map{|d| "#{@app.deploys_path}/#{d}"}

    @sa.remove_old_deploys

    assert_not_called "rm -rf #{removed.join(" ")}"
  end


  def test_revert!
    deploys = %w{ploy1 ploy2 ploy3 ploy4 ploy5}

    @sa.shell.mock :call,
      :args    => ["ls -rc1 #{@app.deploys_path}"],
      :return => "#{deploys.join("\n")}\n"

    @sa.revert!

    assert_server_call "rm -rf #{@app.checkout_path}"
    assert_server_call "ls -rc1 #{@app.deploys_path}"

    last_deploy = "#{@app.deploys_path}/ploy5"
    assert_server_call "ln -sfT #{last_deploy} #{@app.current_path}"
  end


  def test_no_previous_revert!
    @sa.shell.mock :call,
      :args    => ["ls -rc1 #{@app.deploys_path}"],
      :return => "\n"

    @sa.revert!

    assert_server_call "rm -rf #{@app.checkout_path}"
    assert_server_call "ls -rc1 #{@app.deploys_path}"
  end


  def test_run_bundler
    @sa.run_bundler

    assert_dep_install 'bundler'
    assert_server_call "cd #{@app.checkout_path} && gem bundle"
  end


  def test_run_geminstaller
    @sa.run_geminstaller

    assert_dep_install 'geminstaller'
    assert_server_call "cd #{@app.checkout_path} && geminstaller -e"
  end


  def test_sass
    sass_files = %w{file1 file2 file3}

    @sa.sass(*sass_files)

    assert_dep_install 'haml'

    sass_files.each do |file|
      sass_file = "public/stylesheets/sass/#{file}.sass"
      css_file  = "public/stylesheets/#{file}.css"

      assert_server_call \
        "cd #{@app.checkout_path} && sass #{sass_file} #{css_file}"
    end
  end


  def test_shell_env
    assert_equal @sa.shell.env, @sa.shell_env
  end


  def test_symlink_current_dir
    @sa.symlink_current_dir

    assert_server_call "ln -sfT #{@app.checkout_path} #{@app.current_path}"
  end


  def test_upload_tasks
    files = %w{task1 task2}

    @sa.upload_tasks(*files)

    assert_server_call "mkdir -p #{@app.checkout_path}/lib/tasks"

    files.each do |f|
      args = ["#{Sunshine::ROOT}/templates/tasks/#{f}.rake",
              "#{@app.checkout_path}/lib/tasks/#{f}.rake"]

      assert @sa.shell.method_called?(:upload, :args => args)
    end
  end


  def test_upload_tasks_with_remote_path
    files = %w{task1 task2}
    path  = "/path/to/remote/tasks"

    @sa.upload_tasks files[0], files[1], :remote_path => path

    assert_server_call "mkdir -p #{path}"

    files.each do |f|
      args = ["#{Sunshine::ROOT}/templates/tasks/#{f}.rake",
              "#{path}/#{f}.rake"]

      assert @sa.shell.method_called?(:upload, :args => args)
    end
  end


  def test_upload_tasks_with_local_path
    files = %w{task1 task2}
    path  = "/path/to/local/tasks"
    args  = files.dup << {:local_path => path}

    @sa.upload_tasks(*args)

    assert_server_call "mkdir -p #{@sa.checkout_path}/lib/tasks"

    files.each do |f|
      args = ["#{path}/#{f}.rake",
              "#{@sa.checkout_path}/lib/tasks/#{f}.rake"]

      assert @sa.shell.method_called?(:upload, :args => args)
    end
  end


  def test_upload_tasks_all
    files = Dir.glob("templates/tasks/*").map{|f| File.basename(f, ".rake")}

    @sa.upload_tasks

    assert_server_call "mkdir -p #{@app.checkout_path}/lib/tasks"

    files.each do |f|
      args = ["#{Sunshine::ROOT}/templates/tasks/#{f}.rake",
              "#{@app.checkout_path}/lib/tasks/#{f}.rake"]

      assert @sa.shell.method_called?(:upload, :args => args)
    end
  end


  def test_write_script
    @sa.write_script "script_name", "script contents"

    args = ["#{@app.checkout_path}/script_name",
            "script contents", {:flags => "--chmod=ugo=rwx"}]

    assert @sa.shell.method_called?(:make_file, :args => args)

    args = ["#{@app.current_path}/script_name",
            "#{@app.root_path}/script_name"]

    assert @sa.shell.method_called?(:symlink, :args => args)
  end
end
