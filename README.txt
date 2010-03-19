= Sunshine

== Description

Sunshine is an object-oriented api for rack application deployment.

Sunshine is open and it can do a lot! It's meant to be dug into and understood.
Knowing how it works will let you do really neat things: classes are
decoupled as much as possible to allow for optimal flexibility,
and most can be used independently.


== Setup

Installing sunshine:

  gem install sunshine

You can either use sunshine by requiring the gem in your script or
by calling the sunshine command:

  sunshine run my_deploy.rb -e qa


== Deploy Scripts

Writing a Sunshine script is easy:

  options = {
    :name => 'myapp',
    :repo => {:type => :svn, :url => 'svn://blah...'},
    :root_path => '/usr/local/myapp'
  }

  options[:remote_shells] = case Sunshine.deploy_env
  when 'qa'
    ['qa1.svr.com', 'qa2.svr.com']
  else
    'localhost'
  end

  Sunshine::App.deploy(options) do |app|

    app_server = Sunshine::Rainbows.new(app)
    app_server.restart

    Sunshine::Nginx.new(app, :point_to => app_server).restart

  end


The App::deploy and App::new methods also support passing
a path to a yaml file:

  app = Sunshine::App.new("path/to/config.yml")
  app.deploy{|app| Sunshine::Rainbows.new(app).restart }


The yaml file can also be any IO stream whos output will parse to yaml.
This can be ueful for passing the file's DATA and keep all the deploy
information in one place:

    # The following two lines are equivalent:
    app = Sunshine::App.new
    app = Sunshine::App.new Sunshine::DATA

    app.deploy{|app| Sunshine::Rainbows.new(app).restart }

    __END__

    # yaml for app goes here...


Yaml files are read on a deploy-environment basis so its format reflects this:

  ---
  # Default is always inherited by all environments
  :default :
    :name : app_name
    :repo :
      :type : svn
      :url :  svn://subversion/app_name/branches/continuous_integration

    :root_path : /usr/local/app_name

    :remote_shells :
      - - localhost
        - :roles : web db app

  # Setup for qa environment
  :qa :
    :repo :
      :type : svn
      :url :  svn://subversion/app_name/tags/release_0001
    :remote_shells :
      - qa1.servers.com
      - qa2.servers.com

  # Prod inherits top level values from :qa
  :prod :
    :inherits : :qa
    :remote_shells :
      - prod1.servers.com
      - prod2.servers.com

In this example, :prod inherits top level values from :qa (only :repo in this
instance). The :inherits key also supports an array as its value.


== Using rake is great!

Although Sunshine comes with it's own bundle of commands, they should be used
to control deployed apps on remote servers in instances where deploy information
(e.g. your deploy yaml file) is unavailable. Their purpose is to query a server
where Sunshine apps have been deployed and have a nominal amount of information
and control over them. Sunshine control commands are run on a per-server basis.

Most of the time though, you'll want to control the deploy on a per-app basis.
You have the deploy information and you need to do things involving that
specific deploy. Rake tasks are great for that, and Sunshine comes with a
template rake file that you can modify to fit your needs.

You can copy the template rake file to lib/tasks/ by running:
  sunshine --rakefile lib/tasks/.

If you open the file, you'll see a variety of tasks that handle deployment, to
application start/stop/restart-ing, to health checks. Most likely, the two tasks
you'll need to update are the :app (for instantiation) and the :deploy tasks.

First off, if you're using rails, you'll probably want to update "task :app" to
"task :app => :environment" in order to get all the rails environment goodness.
You'll also want to make sure that the @app object gets instantiated with the
proper hash value or yaml file.

Second, you need to update your :deploy task. Add whatever instructions you need
to the @app.deploy block.

And that's it! Try running your Sunshine rake tasks!


== Dependencies

Sunshine has simple, basic dependency support, and relies mostly on preexisting
package manager tools such as apt, yum, or rubygems. Dependencies or packages
can be defined independently, or as a part of a dependency tree
(see Sunshine::DependencyLib). Sunshine has its own internal dependency tree
which can be modified but users can also create their own.


=== User Dependencies

The most common way of using dependencies is through ServerApp:

  server_app.apt_install 'postgresql', 'libxslt'
  server_app.gem_install 'json', :version => '>=1.0.0'

This should be plenty for most users. You can however create simple standalone
package definitions:

  postgresql = Sunshine::Apt.new('postgresql')
  postgresql.install! :call => server_app.shell

You can imagine how this would be useful to do server configuration
with Sunshine:

  server = RemoteShell.new "user@myserver.com"
  server.connect

  %w{postgresql libxslt ruby-full rubygems} do |dep_name|
    Sunshine::Apt.new(dep_name).install! :call => server
  end

Warning: If the :call options isn't specified, the dependency will attempt to
install on the local system.


=== Internal Sunshine Dependencies (advanced)

Sunshine's default dependencies are defined in Sunshine.dependencies and can
be overridden as needed:

  Sunshine.dependencies.get 'rubygems', :type => Sunshine::Yum
  #=> <Sunshine::Yum ... version='1.3.5' >
  # Not what you want? Replace it:

  Sunshine.dependencies.yum 'rubygems', :version => '1.3.2'

Any dependencies added or modified in Sunshine.dependencies are used as a part
of the internal Sunshine workings. Also to note: ServerApp#pkg_manager is
crucial in defining which dependency to use. By default, a server_app's
package manager will be either Yum or Apt depending on availability. That can
be overridden with something like:

  server_app.pkg_manager = Sunshine::Yum

An array can also be given and the server_app will attempt to install available
dependencies according to that type order:

  server_app.pkg_manager = [Sunshine::Tpkg, Sunshine::Yum]

In this instance, if no Tpkg dependency was defined in Sunshine.dependencies,
the server_app will look for a Yum dependency. If you want to ensure all your
server_apps use the same dependency definition, you may consider:

  Sunshine.dependencies.yum 'rubygems', :version => '1.3.2'
  Sunshine.dependencies.apt 'rubygems', :version => '1.3.2'
  # ... and so on


== Deployed Application Control

Sunshine has a variety of commands that allow simple control of
remote or locally deployed applications. These include start, stop, restart
actions to be taken application-wide, as well as querying for the
health and state of the app:

Examples:
  sunshine run deploy_script.rb
  sunshine restart myapp -r user@server.com,user@host.com
  sunshine list myapp myotherapp --health -r user@server.com
  sunshine list myapp --status

The Sunshine commands are as follows:
  add       Register an app with sunshine
  list      Display deployed apps
  restart   Restart a deployed app
  rm        Unregister an app with sunshine
  run       Run a Sunshine script
  start     Start a deployed app
  stop      Stop a deployed app

For more help on sunshine commands, use 'sunshine COMMAND --help'.
For more information about control scripts, see the
Sunshine::App#build_control_scripts method.
