require 'test_helper'

class TestDeployServerApp < Test::Unit::TestCase

  def setup
    mock_svn_response

    @app = mock_app
    @app.repo.extend MockObject

    @dsa = Sunshine::DeployServerApp.new @app,
      "jcastagna@jcast.np.wc1.yellowpages.com"

    @dsa.extend MockOpen4
    @dsa.extend MockObject

    use_deploy_server @dsa
  end


  def test_init
    default_info = {:ports => {}}
    assert_equal default_info, @dsa.info

    assert Sunshine::DeployServer === @dsa
    assert_equal @app, @dsa.app
    assert_equal Hash.new, @dsa.scripts
    assert_equal Array.new, @dsa.roles
  end


  def test_init_roles
    dsa = Sunshine::DeployServerApp.new @app, "host", :roles => "role1 role2"
    assert_equal [:role1, :role2], dsa.roles

    dsa = Sunshine::DeployServerApp.new @app, "host", :roles => %w{role3 role4}
    assert_equal [:role3, :role4], dsa.roles
  end


  def test_add_shell_paths
    @dsa.add_shell_paths "test/path1", "test/path2"
    assert_equal "test/path1:test/path2:$PATH", @dsa.shell_env['PATH']

    @dsa.add_shell_paths "test/path3", "test/path4"
    assert_equal "test/path3:test/path4:test/path1:test/path2:$PATH",
      @dsa.shell_env['PATH']
  end


  def test_build_control_scripts
    @dsa.scripts[:start] << "start"
    @dsa.scripts[:stop]  << "stop"
    @dsa.scripts[:custom] << "custom"

    @dsa.build_control_scripts

    [:start, :stop, :custom].each do |script|
      content = @dsa.make_bash_script script, @dsa.scripts[script]
      assert @dsa.method_called?(:write_script, :args => [script, content])
    end

    content = @dsa.make_env_bash_script
    assert @dsa.method_called?(:write_script, :args => ["env", content])

    content = @dsa.make_bash_script :restart,
      ["#{@dsa.app.deploy_path}/stop", "#{@dsa.app.deploy_path}/start"]
    assert @dsa.method_called?(:write_script, :args => [:restart, content])
  end


  def test_build_deploy_info_file
    args = ["#{@app.checkout_path}/info", @dsa.get_deploy_info.to_yaml]

    @dsa.build_deploy_info_file

    assert @dsa.method_called?(:make_file, :args => args)

    args = ["#{@app.current_path}/info", "#{@app.deploy_path}/info"]

    assert @dsa.method_called?(:symlink, :args => args)
  end


  def test_checkout_codebase
    @dsa.checkout_codebase
    repo = @dsa.app.repo
    args = [@app.checkout_path, @dsa]

    assert repo.method_called?(:checkout_to, :args => args)

    info = @app.repo.checkout_to @app.checkout_path, @dsa
    assert_equal info, @dsa.info[:scm]
  end


  def test_get_deploy_info
    test_info = {
      :deployed_at => Time.now.to_s,
      :deployed_as => @dsa.call("whoami"),
      :deployed_by => Sunshine.console.user,
      :deploy_name => File.basename(@app.checkout_path),
      :roles       => @dsa.roles,
      :path        => @app.deploy_path
    }.merge @dsa.info

    deploy_info = @dsa.get_deploy_info

    deploy_info.each do |key, val|
      next if key == :deployed_at
      assert_equal test_info[key], val
    end
  end


  def test_install_deps
    nginx_dep = Sunshine::Dependencies['nginx']

    @dsa.install_deps "ruby", nginx_dep

    assert_dep_install 'nginx'
    assert_dep_install 'ruby'
  end


  def test_install_gems_bundler
    @dsa.mock :file?,
      :args => ["#{@app.checkout_path}/Gemfile"], :return => true

    @dsa.install_gems

    assert @dsa.method_called?(:run_bundler)
  end


  def test_install_gems_geminstaller
    @dsa.mock :file?,
      :args => ["#{@app.checkout_path}/config/geminstaller.yml"],
      :return => true

    @dsa.install_gems

    assert @dsa.method_called?(:run_geminstaller)
  end


  def test_make_app_directories
    @dsa.make_app_directories

    assert_server_call "mkdir -p #{@app.directories.join(" ")}"
  end


  def test_make_bash_script
    app_script = @dsa.make_bash_script "blah", [1,2,3,4]

    assert_bash_script "blah", [1,2,3,4], app_script
  end


  def test_make_env_bash_script
    @dsa.env = {"BLAH" => "blarg", "HOME" => "/home/blah"}

    test_script = "#!/bin/bash\nenv BLAH=blarg HOME=/home/blah \"$@\""

    assert_equal test_script, @dsa.make_env_bash_script
  end


  def test_rake
    @dsa.rake "db:migrate"

    assert_dep_install 'rake'
    assert_server_call "cd #{@app.checkout_path} && rake db:migrate"
  end


  def test_register_as_deployed
    Sunshine::AddCommand.extend MockObject unless
      MockObject === Sunshine::AddCommand

    @dsa.register_as_deployed

    args = [@app.deploy_path, {'servers' => [@dsa]}]
    assert Sunshine::AddCommand.method_called?(:exec, :args => args)
  end


  def test_remove_old_deploys
    Sunshine.setup 'max_deploy_versions' => 3

    deploys = %w{ploy1 ploy2 ploy3 ploy4 ploy5}

    @dsa.mock :call,
      :args   => ["ls -1 #{@app.deploys_dir}"],
      :return => "#{deploys.join("\n")}\n"

    removed = deploys[0..1].map{|d| "#{@app.deploys_dir}/#{d}"}

    @dsa.remove_old_deploys

    assert_server_call "rm -rf #{removed.join(" ")}"
  end


  def test_remove_old_deploys_unnecessary
    Sunshine.setup 'max_deploy_versions' => 5

    deploys = %w{ploy1 ploy2 ploy3 ploy4 ploy5}

    @dsa.mock :call,
      :args   => ["ls -1 #{@app.deploys_dir}"],
      :return => "#{deploys.join("\n")}\n"

    removed = deploys[0..1].map{|d| "#{@app.deploys_dir}/#{d}"}

    @dsa.remove_old_deploys

    assert_not_called "rm -rf #{removed.join(" ")}"
  end


  def test_revert!
    Sunshine::StartCommand.extend MockObject unless
      MockObject === Sunshine::StartCommand

    deploys = %w{ploy1 ploy2 ploy3 ploy4 ploy5}

    @dsa.mock :call,
      :args    => ["ls -rc1 #{@app.deploys_dir}"],
      :return => "#{deploys.join("\n")}\n"

    @dsa.revert!

    assert_server_call "rm -rf #{@app.checkout_path}"
    assert_server_call "ls -rc1 #{@app.deploys_dir}"

    last_deploy = "#{@app.deploys_dir}/ploy5"
    assert_server_call "ln -sfT #{last_deploy} #{@app.current_path}"

    args = [[@app.name], {'servers' => [@dsa], 'force' => true}]
    assert Sunshine::StartCommand.method_called? :exec, :args => args
  end


  def test_no_previous_revert!
    @dsa.crontab.extend MockObject

    @dsa.mock :call,
      :args    => ["ls -rc1 #{@app.deploys_dir}"],
      :return => "\n"

    @dsa.revert!

    assert_server_call "rm -rf #{@app.checkout_path}"
    assert_server_call "ls -rc1 #{@app.deploys_dir}"

    assert @dsa.crontab.method_called?(:delete!, :args => [@dsa])
  end


  def test_run_bundler
    @dsa.run_bundler

    assert_dep_install 'bundler'
    assert_server_call "cd #{@app.checkout_path} && gem bundle"
  end


  def test_run_geminstaller
    @dsa.run_geminstaller

    assert_dep_install 'geminstaller'
    assert_server_call "cd #{@app.checkout_path} && geminstaller -e"
  end


  def test_sass
    sass_files = %w{file1 file2 file3}

    @dsa.sass(*sass_files)

    assert_dep_install 'haml'

    sass_files.each do |file|
      sass_file = "public/stylesheets/sass/#{file}.sass"
      css_file  = "public/stylesheets/#{file}.css"

      assert_server_call \
        "cd #{@app.checkout_path} && sass #{sass_file} #{css_file}"
    end
  end


  def test_shell_env
    assert_equal @dsa.env, @dsa.shell_env
  end


  def test_symlink_current_dir
    @dsa.symlink_current_dir

    assert_server_call "ln -sfT #{@app.checkout_path} #{@app.current_path}"
  end


  def test_upload_tasks
    files = %w{task1 task2}

    @dsa.upload_tasks(*files)

    assert_server_call "mkdir -p #{@app.checkout_path}/lib/tasks"

    files.each do |f|
      args = ["templates/tasks/#{f}.rake",
              "#{@app.checkout_path}/lib/tasks/#{f}.rake"]

      assert @dsa.method_called?(:upload, :args => args)
    end
  end


  def test_upload_tasks_with_path
    files = %w{task1 task2}
    path  = "/path/to/remote/tasks"

    @dsa.upload_tasks files[0], files[1], :remote_path => path

    assert_server_call "mkdir -p #{path}"

    files.each do |f|
      args = ["templates/tasks/#{f}.rake",
              "#{path}/#{f}.rake"]

      assert @dsa.method_called?(:upload, :args => args)
    end
  end


  def test_upload_tasks_all
    files = Dir.glob("templates/tasks/*").map{|f| File.basename(f, ".rake")}

    @dsa.upload_tasks

    assert_server_call "mkdir -p #{@app.checkout_path}/lib/tasks"

    files.each do |f|
      args = ["templates/tasks/#{f}.rake",
              "#{@app.checkout_path}/lib/tasks/#{f}.rake"]

      assert @dsa.method_called?(:upload, :args => args)
    end
  end


  def test_write_script
    @dsa.write_script "script_name", "script contents"

    args = ["#{@app.checkout_path}/script_name",
            "script contents", {:flags => "--chmod=ugo=rwx"}]

    assert @dsa.method_called?(:make_file, :args => args)

    args = ["#{@app.current_path}/script_name",
            "#{@app.deploy_path}/script_name"]

    assert @dsa.method_called?(:symlink, :args => args)
  end
end
