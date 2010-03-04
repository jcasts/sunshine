require 'sunshine/presets/atti'


Sunshine::AttiApp.deploy do |app|

  app.shell_env "NLS_LANG"        => "American_America.UTF8",
                "TNS_ADMIN"       => "#{app.current_path}/config",
                "ORACLE_HOME"     => "/usr/lib/oracle/11.2/client64",
                "LD_LIBRARY_PATH" => "/usr/lib/oracle/11.2/client64/lib"

  app.install_deps 'libxml2-devel', 'libxslt-devel', 'sqlite', 'sqlite-devel',
                   'libaio', 'ruby-devel',
                   'isolate', 'activerecord-oracle_enhanced-adapter'

  app.install_gems


  # Don't decrypt the db yml file for these environments
  non_secure_envs = %w{cruise integration test development}
  secure_db = !non_secure_envs.include?(app.deploy_env)

  if secure_db
    app.decrypt_db_yml :role => :db
  else
    app.rake "config/database.yml", :role => :db
  end

  app.rake 'db:migrate', :role => :db


  sass_yml_file = "#{app.checkout_path}/config/asset_packages.yml"
  sass_yml      = app.deploy_servers.first.call "cat #{sass_yml_file}"
  sass_files    = YAML.load(sass_yml)['stylesheets']
  sass_files    = sass_files[0]['all'].concat sass_files[1]['brochure']

  sass_files.delete_if{|s| s=~ /^960\//}

  app.sass sass_files, :role => :cdn
  app.rake 'asset:packager:build_all', :role => :cdn


  delayed_job = Sunshine::DelayedJob.new app
  delayed_job.restart

  mail = Sunshine::ARSendmail.new app
  mail.restart

  unicorn = Sunshine::Unicorn.new app, :port => 10001, :processes => 8
  unicorn.restart

  nginx = Sunshine::Nginx.new app, :point_to => unicorn, :port => 10000
  nginx.restart
end


__END__

:default:
  :name: webbuzz

  :repo:
    :type:  git
    :url:   git://buzzdotcom.np.wc1.yellowpages.com/buzz.git
    :flags: "--depth 5"

  :deploy_path: ~nextgen/buzz

  :deploy_servers:
    - - jcast.np.wc1.yellowpages.com
      - :roles: web db app cdn mail dj

    - - sunny.np.wc1.yellowpages.com
      - :roles: web db app cdn mail dj
