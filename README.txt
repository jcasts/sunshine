= Sunshine

== Description

Sunshine is a deployment gem that provides a light, consistant api for
application deployment.


== Setup

Installing sunshine:

  gem install sunshine

You can either use sunshine by requiring the gem in your deploy script or
by calling the sunshine command:

  sunshine my_deploy.rb -e qa


== Deploy Scripts

Writing a Sunshine config script is easy:

  options = {
    :name => 'myapp',
    :repo => {:type => :svn, :url => 'svn://blah...'},
    :deploy_path => '/usr/local/myapp',
    :deploy_servers => ['user@someserver.com']
  }

  Sunshine::App.deploy(options) do |app|

    app_server = Sunshine::Rainbows.new(app)
    app_server.restart

    Sunshine::Nginx.new(app, :point_to => app_server).restart

  end

