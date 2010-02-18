require 'sunshine/presets/atti'

# Dependencies for Buzz

Sunshine::Dependencies.yum 'libxml2-devel'
Sunshine::Dependencies.yum 'libxslt-devel'
Sunshine::Dependencies.yum 'sqlite'
Sunshine::Dependencies.yum 'sqlite-devel'

Sunshine::Dependencies.gem 'ruby-oci8'
Sunshine::Dependencies.gem 'activerecord-oracle_enhanced-adapter' do
  requires 'ruby-oci8'
end

Sunshine::Dependencies.gem 'isolate'


# Deploy!

Sunshine::AttiApp.deploy do |app|

  app.shell_env "NLS_LANG"        => "American_America.UTF8",
                "TNS_ADMIN"       => "#{app.current_path}/config",
                "ORACLE_HOME"     => "/usr/lib/oracle/10.2.0.3/client64",
                "LD_LIBRARY_PATH" => "/usr/lib/oracle/10.2.0.3/client64/lib"

  app.install_deps 'libxml2-devel', 'libxslt-devel', 'sqlite', 'sqlite-devel',
                   'isolate', 'activerecord-oracle_enhanced-adapter'

  app.deploy_servers.call "cd #{app.deploy_path} && tpkg"


  #app.rake 'newb'
  app.install_gems

  app.rake 'config/database.yml'
  app.rake 'db:migrate', app.deploy_servers.find(:role => :db)


  cdn_servers = app.deploy_servers.find :role => :cdn

  sass_yml_file = "#{app.checkout_path}/config/asset_packages.yml"
  sass_yml      = cdn_servers.first.call "cat #{sass_yml_file}"
  sass_files    = YAML.load(sass_yml)['stylesheets'][0]['all']

  sass_files.delete_if{|s| s=~ /^960\//}

  app.sass sass_files, cdn_servers
  app.rake 'asset:packager:build_all', cdn_servers


  mail    = Sunshine::ARSendmail.new app
  mail.restart

  unicorn = Sunshine::Unicorn.new app, :port => 10001, :processes => 8
  unicorn.restart

  nginx   = Sunshine::Nginx.new app, :point_to => unicorn, :port => 10000
  nginx.restart


  app.health.enable
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
      - :roles: web db app cdn mail
