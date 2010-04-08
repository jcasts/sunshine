require 'sunshine'

Sunshine.setup 'sudo'          => 'app_user',
               'trace'         => true,
               'web_directory' => "/var/www"

##
# Deploy!

Sunshine::App.deploy :name => 'my_app' do |app|

  rainbows = Sunshine::Rainbows.new(app, :port => 5001)

  nginx = Sunshine::Nginx.new(app, :point_to => rainbows, :port => 5000)

  app.run_geminstaller

  rainbows.setup
  nginx.setup
end


__END__

:default:
  :repo:
    :type: svn
    :url:  svn://subversion/path/to/<%= name %>/tags/release001

  :remote_shells:
    - <%= deploy_env %>-<%= name %>.my_server.com
