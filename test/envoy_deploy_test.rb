
Sunshine::Dependencies::Gem.sudo = true

Sunshine::App.deploy do |app|

  rainbows = Sunshine::Rainbows.new(app, :port => 5001)

  nginx = Sunshine::Nginx.new(app, :point_to => rainbows, :port => 5000)
  nginx.log_files :impressions => "#{app.log_path}/impressions.log",
                  :stderr      => "#{app.log_path}/error.log",
                  :stdout      => "#{app.log_path}/access.log"

  app.install_gems

  app.upload_tasks 'app', 'common', 'tpkg'
  # app.rake 'db:migrate', app.deploy_servers.find(:role => :db)

  rainbows.restart
  nginx.restart

  app.health.enable
end


__END__

:default:
  :name: envoy
  :repo:
    :type: svn
    :url:  svn://subversion.flight.yellowpages.com/webtools/webservices/envoy/tags/200912.2-WAT-235-release

  :deploy_path: ~/envoy

  :deploy_servers:
    - - jcastagna@jcast.np.wc1.yellowpages.com
      - :roles: web db app
