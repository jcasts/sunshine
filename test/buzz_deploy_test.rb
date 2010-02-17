
# Dependencies that need fixing for ATTi VMs

Sunshine::Dependencies.tpkg 'git'
Sunshine::Dependencies.yum 'ruby-devel', :arch => 'x86_64'


# Extra dependencies for Buzz

Sunshine::Dependencies.gem 'isolate'
Sunshine::Dependencies.yum 'libxml2-devel'
Sunshine::Dependencies.yum 'libxslt-devel'
Sunshine::Dependencies.yum 'sqlite'
Sunshine::Dependencies.yum 'sqlite-devel'

Sunshine::Dependencies::Yum.sudo = true
Sunshine::Dependencies::Gem.sudo = true

# Deploy!

Sunshine::App.deploy do |app|

  app.shell_env "ORACLE_HOME" => "/usr/lib/oracle/10.2.0.3/client64",
                "NLS_LANG"    => "American_America.UTF8",
                "TNS_ADMIN"   => "#{app.current_path}/config"

  app.install_deps 'libxml2-devel', 'libxslt-devel',
                   'sqlite', 'sqlite-devel', 'isolate'

  app.rake 'newb'

  app.deploy_servers.call "cd #{app.deploy_path} && tpkg"


  mail    = Sunshine::ARSendmail.new app
  mail.restart

  unicorn = Sunshine::Unicorn.new app, :port => 10001
  unicorn.restart

  nginx   = Sunshine::Nginx.new app, :point_to => unicorn, :port => 10000
  nginx.restart


  app.health.enable
end


__END__

:default:
  :name: webbuzz
  :deploy_name: first_deploy

  :repo:
    :type:  git
    :url:   git://buzzdotcom.np.wc1.yellowpages.com/buzz.git
    :flags: "--depth 5"

  :deploy_path: ~nextgen/buzz

  :deploy_servers:
    - - jcast.np.wc1.yellowpages.com
      - :roles: web db app mail
