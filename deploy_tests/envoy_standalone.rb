require 'sunshine'

Sunshine.setup 'sudo'          => 'nextgen',
               'trace'         => true,
               'web_directory' => "~nextgen"

##
# Deploy!

Sunshine::App.deploy :name => 'envoy' do |app|

  app.add_shell_paths '/usr/sbin'

  rainbows = Sunshine::Rainbows.new(app, :port => 5001)

  nginx = Sunshine::Apache.new(app, :point_to => rainbows, :port => 5000)

  app.run_geminstaller

  rainbows.restart
  nginx.restart
end


__END__

:default:
  :repo:
    :type: svn
    :url:  svn://subversion.flight.yellowpages.com/webtools/webservices/<%= name %>/tags/200912.2-WAT-235-release

  :remote_shells:
#   - <%= deploy_env %>-<%= name %>.np.wc1.yellowpages.com
    - sunny.np.wc1.yellowpages.com
