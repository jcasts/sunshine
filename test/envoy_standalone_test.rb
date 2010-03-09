require 'sunshine'
Sunshine.setup 'sudo'          => 'nextgen',
               'trace'         => true,
               'web_directory' => "~nextgen"

require 'sunshine/presets/atti'

##
# Deploy!

Sunshine::AttiApp.deploy do |app|

  rainbows = Sunshine::Rainbows.new(app, :port => 5001)

  nginx = Sunshine::Nginx.new(app, :point_to => rainbows, :port => 5000)
  nginx.log_files :impressions => "#{app.log_path}/impressions.log",
                  :stderr      => "#{app.log_path}/error.log",
                  :stdout      => "#{app.log_path}/access.log"

  app.install_gems

  app.upload_tasks 'app', 'common', 'tpkg'

  rainbows.restart
  nginx.restart
end


__END__

:default:
  :repo:
    :type: svn
    :url:  svn://subversion.flight.yellowpages.com/webtools/webservices/envoy/tags/200912.2-WAT-235-release

  :deploy_servers:
#   - %e-%n.np.wc1.yellowpages.com
    - jcast.np.wc1.yellowpages.com
