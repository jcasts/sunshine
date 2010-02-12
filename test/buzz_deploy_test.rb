
# Dependencies that need fixing for ATTi VMs

Sunshine::Dependencies.tpkg 'git'
Sunshine::Dependencies.yum 'ruby-devel', :arch => 'x86_64'


# Extra dependencies for Buzz

Sunshine::Dependencies.gem 'isolate'
Sunshine::Dependencies.yum 'libxml2-devel'
Sunshine::Dependencies.yum 'libxslt-devel'
Sunshine::Dependencies.yum 'sqlite'
Sunshine::Dependencies.yum 'sqlite-devel'


# Deploy!

Sunshine::App.deploy do |app|

  app.install_deps 'libxml2-devel', 'libxslt-devel',
                   'sqlite', 'sqlite-devel', 'isolate'

  app.rake 'newb'


  app.upload_tasks 'tpkg'
  app.deploy_servers.call "cd #{app.deploy_path} && tpkg"

  app.health.enable


  unicorn = Sunshine::Unicorn.new app, :port => 10001
  nginx   = Sunshine::Nginx.new app, :point_to => unicorn, :port => 10000

  unicorn.restart
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
    - - jcastagna@jcast.np.wc1.yellowpages.com
      - :roles: web db app
