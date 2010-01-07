require 'sunshine'

Sunshine::App.deploy "test/fixtures/app_configs/test_app.yml" do |app|

  app.shell_env "RAKE_ENV" => "integration"

  rainbows = Sunshine::Rainbows.new(app, :port => 5001)

  nginx = Sunshine::Nginx.new(app, :point_to => rainbows, :port => 5000)
  nginx.bin = "/home/ypc/sbin/nginx"  # "/home/t/sbin/nginx" #=> tpkg path
  nginx.log_files :impressions => "#{app.log_path}/impressions.log",
                  :stderr      => "#{app.log_path}/error.log",
                  :stdout      => "#{app.log_path}/access.log"

  app.install_gems

  app.upload_tasks 'app', 'common', 'tpkg'
  # app.rake 'db:migrate', app.deploy_servers.find(:role => :db)

  rainbows.restart
  nginx.restart

  app.health.enable!

end

