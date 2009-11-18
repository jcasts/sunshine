require 'sunshine'

Sunshine::App.deploy "test/fixtures/app_configs/test_app.yml" do |app|

  rainbows = Sunshine::Rainbows.new(app, :port => 5001)

  nginx = Sunshine::Nginx.new(app, :point_to => rainbows, :port => 5000)
  nginx.bin = "/home/t/sbin/nginx"
  nginx.log_files :impressions => "#{app.shared_path}/log/impressions.log",
                  :stderr      => "#{app.shared_path}/log/error.log",
                  :stdout      => "#{app.shared_path}/log/access.log"

  app.install_gems

  rainbows.restart
  nginx.restart

  app.health.enable!

end

