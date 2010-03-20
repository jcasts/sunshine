##
# Deploy!

Sunshine::App.deploy do |app|

  rainbows = Sunshine::Rainbows.new(app, :port => 5001)

  nginx = Sunshine::Nginx.new(app, :point_to => rainbows, :port => 5000)

  app.run_geminstaller

  rainbows.restart
  nginx.restart
end


__END__

:default:
  :name: envoy
  :repo:
    :type: svn
    :url:  svn://subversion.flight.yellowpages.com/webtools/webservices/envoy/tags/200912.2-WAT-235-release

  :root_path: ~nextgen/envoy

  :remote_shells:
    - - jcastagna@jcast.np.wc1.yellowpages.com
      - :roles: web db app
