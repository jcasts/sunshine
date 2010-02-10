
Sunshine::Dependencies.tpkg 'git'
Sunshine::Dependencies.gem 'isolate'


Sunshine::App.deploy do |app|

  app.install_deps 'isolate'

  app.rake 'newb'


  app.upload_tasks 'tpkg'
  app.install_deps 'tpkg'
  app.deploy_servers.run "cd #{app.deploy_path} && tpkg"

  app.health.enable


  unicorn   = Sunshine::Unicorn.new app, :port => 10001

  nginx     = Sunshine::Nginx.new app, :point_to => unicorn, :port => 10000
  nginx.bin = "/home/ypc/sbin/nginx"

  unicorn.restart
  nginx.restart
end


__END__

:default:
  :name: webbuzz
  :repo:
    :type:  git
    :url:   nextgen@buzzdotcom.np.wc1.yellowpages.com:buzz.git
    :flags: "--depth 5"

  :deploy_path: /usr/local/nextgen/buzz

  :deploy_servers:
    - jcastagna@jcast.np.wc1.yellowpages.com
