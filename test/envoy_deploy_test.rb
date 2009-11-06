require 'sunshine'

Sunshine::App.deploy "test/fixtures/app_configs/test_app.yml" do |app|

  app.install_gems

  rainbows = Sunshine::Rainbows.new(app, :port => 5001)
  nginx = Sunshine::Nginx.new(app, :point_to => rainbows, :port => 5000)

  rainbows.restart
  nginx.restart

end

