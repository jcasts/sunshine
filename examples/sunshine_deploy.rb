Sunshine::App.deploy do |app|

  app.shell_env "NLS_LANG"        => "American_America.UTF8",
                "TNS_ADMIN"       => "#{app.current_path}/config",
                "ORACLE_HOME"     => "/usr/lib/oracle/11.2/client64",
                "LD_LIBRARY_PATH" => "/usr/lib/oracle/11.2/client64/lib"

  app.gem_install 'isolate', :version => '1.3.0'

  app.yum_install 'libxml2-devel', 'libxslt-devel', 'libaio', 'sqlite-devel',
                  'sqlite', 'ruby-devel', 'activerecord-oracle_enhanced-adapter'

  app.run_bundler

  app.with_filter :role => :db do

    app.rake 'config/database.yml'
    app.rake 'db:migrate'
  end

  app.with_filter :role => :cdn do

    sass_yml_file = "#{app.checkout_path}/config/asset_packages.yml"
    sass_yml      = app.server_apps.first.shell.call "cat #{sass_yml_file}"
    sass_files    = YAML.load(sass_yml)['stylesheets']

    app.sass sass_files
    app.rake 'asset:packager:build_all'
  end


  Sunshine::DelayedJob.new(app).setup
  Sunshine::ARSendmail.new(app).setup

  unicorn = Sunshine::Unicorn.new app, :port => 10001, :processes => 8
  nginx   = Sunshine::Nginx.new app, :point_to => unicorn

  unicorn.setup
  nginx.setup
end


__END__

:default:
  :repo:
    :type:  git
    :url:   git://my_git_server.com/app_name.git
    :flags: "--depth 5"

  :root_path: ~my_user/app_name

  :remote_shells:
    - myserver1.com
    - myserver2.com
