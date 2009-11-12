require 'sunshine'

app = Sunshine::App.deploy "test/fixtures/app_configs/test_app.yml" do |app|

  rainbows = Sunshine::Rainbows.new(app, :port => 5001)
  nginx = Sunshine::Nginx.new(app, :point_to => rainbows, :port => 5000)

  app.install_gems

  rainbows.restart
  nginx.restart

  app.health.enable!

end

