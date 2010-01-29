= Sunshine

== Description

Sunshine is a deployment gem that provides a light, consistant api for
application deployment.


== Setup

Installing sunshine:

  gem install sunshine

You can either use sunshine by requiring the gem in your deploy script or
by calling the sunshine command:

  sunshine deploy my_deploy.rb -e qa


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


The App::deploy and App::new methods also support passing
a path to a yaml file:

  app = Sunshine::App.new("path/to/config.yml")
  app.deploy!{|app| Sunshine::Rainbows.new(app).restart }


== Deployed Application Control

Sunshine has a variety of commands that allow simple control of
remote or locally deployed applications. These include start, stop, restart
actions to be taken application-wide, as well as querying for the
health and state of the app.

Examples:
  sunshine deploy deploy_script.rb
  sunshine restart myapp -r user@server.com,user@host.com
  sunshine list myapp myotherapp --health -r user@server.com
  sunshine list myapp --status

The Sunshine commands are as follows:
  add       Register an app with sunshine
  deploy    Run a deploy script
  list      Display deployed apps
  restart   Restart a deployed app
  rm        Unregister an app with sunshine
  start     Start a deployed app
  stop      Stop a deployed app

For more help on sunshine commands, use 'sunshine COMMAND --help'.
For more information about control scripts, see the
Sunshine::App#build_control_scripts method.
