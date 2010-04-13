= Sunshine

http://github.com/yaksnrainbows/sunshine

http://betalabs.yellowpages.com/


== Description

Sunshine is a framework for rack and rails application deployment.

This gem was made possible by the sponsoring of AT&T Interactive
(http://attinteractive.com).


== Setup and Usage

Installing sunshine:

  $ gem install sunshine

Call sunshine to create the config file:

  $ sunshine

  Missing config file was created for you: /Users/jsmith/.sunshine

  --- 
  web_directory: /var/www
  max_deploy_versions: 5
  auto_dependencies: true
  level: info
  auto: false
  remote_checkouts: false
  deploy_env: :development


You can either use sunshine by requiring the gem in your script, such as
in a rakefile (which is more common):

  $ rake sunshine:deploy

Or you can also call built-in sunshine commands:

  $ sunshine run my_deploy.rb -e qa


== Rake Deploy Tasks in 5 Minutes

Although Sunshine comes with it's own bundle of commands, they should be used
to control deployed apps on remote servers in instances where deploy information
(e.g. your deploy yaml file) is unavailable. Their purpose is to query a server
where Sunshine apps have been deployed and have a nominal amount of information
and control over them. Sunshine control commands are run on a per-server basis.

Most of the time, you'll want to control the deploy on a per-app basis.
You have the deploy information and you need to do things involving that
specific deploy. Rake tasks are great for that, and Sunshine comes with a
template rake file that you can modify to fit your needs.

You can copy the template rake file to lib/tasks/ by running:
  $ sunshine --rakefile lib/tasks/.

If you open the file, you'll see a variety of tasks that handle deployment, to
application start/stop/restart-ing, to health checks. Most likely, the two tasks
you'll need to update are the :app (for instantiation) and the :deploy tasks.

First off, if you're using rails, you'll probably want to update "task :app" to
"task :app => :environment" in order to get all the rails environment goodness.
You'll also want to make sure that the @app object gets instantiated with the
proper hash value or yaml file.

Second, you need to update your :deploy task. Add whatever instructions you need
to the @app.deploy block. Here's a sample of completed :app and :deploy tasks:

  namespace :sunshine do

    desc "Instantiate Sunshine"
    task :app => :environment do
      Sunshine.setup 'sudo'          => 'app_user',
                     'web_directory' => '/var/www',
                     'deploy_env'    => Rails.environment

      @app = Sunshine::App.new \
        :repo => Sunshine::SvnRepo.new("svn://subversion/repo/tags/release001"),
        :remote_shells => 'user@my_server.com'
    end


    desc "Deploy the app"
    task :deploy => :app do
      Sunshine.setup 'trace' => true

      @app.deploy do |app|

        rainbows = Sunshine::Rainbows.new app, :port => 5001

        nginx = Sunshine::Nginx.new app, :point_to => rainbows

        app.run_geminstaller

        rainbows.setup
        nginx.setup
      end
    end

    ...
  end

And that's it! Try running your Sunshine rake tasks!

  rake sunshine:app             # Instantiate Sunshine
  rake sunshine:db_migrate      # Run db:migrate on remote :db servers
  rake sunshine:deploy          # Deploy the app
  rake sunshine:health          # Get the health state
  rake sunshine:health:disable  # Turn off health check
  rake sunshine:health:enable   # Turn on health check
  rake sunshine:health:remove   # Remove health check
  rake sunshine:info            # Get deployed app info
  rake sunshine:restart         # Run the remote restart script
  rake sunshine:start           # Run the remote start script
  rake sunshine:status          # Check if the deployed app is running
  rake sunshine:stop            # Run the remote stop script


== Understanding Deployment

=== The App Class

Writing a Sunshine script is easy.
App objects are the core of Sunshine deployment. The Sunshine paradygm
is to construct an app object, and run custom deploy code by passing
a block to its deploy method:

  options = {
    :name => 'myapp',
    :repo => {:type => :svn, :url => 'svn://blah...'},
    :root_path => '/usr/local/myapp'
  }

  options[:remote_shells] =
    case Sunshine.deploy_env
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

An App holds information about where to deploy an application to and
how to deploy it, as well as many convenience methods to setup and
manipulate the deployment process. Most of these methods support passing
remote shell find options:

  app.rake 'db:migrate', :role => :db
  app.deploy :host => 'server1.com'

See Sunshine::App#find for more information.


=== Working With Environments

Environment specific setups can be accomplished in a few ways. The most
obvious way is to create a different script for each environment. You can
also define the App's constructor hash on a per-environment basis
(as seen above), which gives you lots of control.
That said, the App class also provides a mechanism for environment handling
using configuration files.
The App::new methods support passing a path to a yaml config file:

  app = Sunshine::App.new("path/to/config.yml")
  app.deploy{|app| Sunshine::Rainbows.new(app).restart }


The yaml file can also be any IO stream who's output will parse to yaml.
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
All environments also inherit from the :default environment. The :default is
also used if the app's deploy_env is not found in the config.

Finally, yaml configs get parsed by erb, exposing any options passed to the
App's constuctor, along with the deploy environment, letting your write configs
such as:

  # deploy.rb

  app = App.new "deploy.yml", :name => "my_app", :deploy_name => "release_001"


  # deploy.yml
  ---
  :default :
    :repo :
      :type : svn
      :url :  svn://subversion/<%= name %>/tags/<%= deploy_name %>

    :remote_shells :
      - <%= deploy_env %>1.<%= name %>.domain.com
      - <%= deploy_env %>2.<%= name %>.domain.com

See Sunshine::App for more information.


== Servers

=== Basics

Sunshine lets you install and setup server applications to run your app on.
The typical approach to serving ruby applications is to run Nginx or Apache
as a load balancer in front of a backend such as Thin, or Mongrels.
Using Sunshine, this is most commonly defined as a part of the deploy process:

  app.deploy do |app|
    backend = Sunshine::Thin.new app, :port => 5000
    nginx   = Sunshine::Nginx.new app, :point_to => backend

    backend.setup
    nginx.setup
  end

When a new Server is instantiated and its setup method is run, it is added to
the app's control scripts. This means that when the deploy is complete, those
servers can be controlled by the app's start/stop/restart/status methods.


=== Load Balancing

Since frontend servers support load balancing, you can also point them to
server clusters:

  backend = Sunshine::Thin.new_cluster 10, app, :port => 5000
  nginx   = Sunshine::Nginx.new app, :point_to => backend

  backend.setup
  nginx.setup

In this instance, Nginx will know to forward requests to the cluster of Thin
servers created. You could do this more explicitely with the following:

  backend = Array.new

  5000.upto(5009) do |port|
    thin = Sunshine::Thin.new app, :port => port, :name => "thin.#{port}"
    thin.setup

    backend << thin
  end

  Sunshine::Nginx.new app, :point_to => backend


=== Phusion Passenger

If you are running a lower traffic application, Phusion Passenger is available
for both Nginx and Apache. Passenger will be used by default if no backend
is specified. You could have an Nginx Passenger setup on port 80 with a
single line:

  Sunshine::Nginx.new(app).setup

Easy!

Servers let you do much more configuration with log files, config files, etc.
For more information, see Sunshine::Server.


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

  %w{postgresql libxslt ruby-full rubygems}.each do |dep_name|
    Sunshine::Apt.new(dep_name).install! :call => server
  end

Warning: If the :call options isn't specified, the dependency will attempt to
install on the local system.

See Sunshine::Dependency for more information.

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

Note: You can disable automatic dependency installation by setting Sunshine's
auto_dependencies config to false.


== Using Permissions

In order to deploy applications successfully, it's important to know how,
where, and when to use permissions in Sunshine deploy scripts.

=== The Shell Class

The primary handler of permissions is the Sunshine::Shell class. Since all
commands are run through a Shell object, it naturally handles permission
changes. The following will create a new remote shell which is logged into
as user "bob" but will use root to perform all calls:

  # The following two lines are equivalent:
  svr = Sunshine::RemoteShell.new "bob@myserver.com", :sudo => true
  svr = Sunshine::RemoteShell.new "myserver.com", :user => "bob" :sudo => true

Sudo can also be set after instantiation. Let's change the permissions back to
its default:

  svr.sudo = nil

You can of course also run single commands with a one-off sudo setting:

  svr.call "whoami", :sudo => true
  #=> "root"

Shell sudo values are important! Depending on what the value of shell.sudo is,
behavior will change dramatically:

- sudo = true   -> sudo -H command
- sudo = 'root' -> sudo -H -u root command
- sudo = 'usr'  -> sudo -H -u usr command
- sudo = false  -> enforce never using sudo
- sudo = nil    -> passthrough (don't care)

Here are a few examples of these values being used:

  svr = Sunshine::RemoteShell.new "bob@myserver.com", :sudo => true

  svr.call "whoami"                   #=> root
  svr.call "whoami", :sudo => "usr"   #=> usr
  svr.call "whoami", :sudo => nil     #=> root
  svr.call "whoami", :sudo => false   #=> bob


These values are crucial as other Sunshine classes have and pass around other
sudo requirements/values to shell objects.


=== Who Affects Sudo

There are 3 main places to beware of how sudo gets used.

==== Apps

The first, most obvious place is the App class:

  app.sudo = "bob"
  app.server_apps.first.shell.sudo #=> "bob"

  app.sudo = true
  app.server_apps.first.shell.sudo #=> true

Since the App class effectively owns the shells it uses, setting sudo on the
App will permanently change the sudo value of its shells.

Note: You may notice that you can set a sudo config value on the Sunshine
module. This is used for the default value of Sunshine::App#sudo and is passed
along to an app's shells on instantiation.


==== Dependencies

Since Sunshine also deals with installing dependencies, the Dependency class
and its children all have a class level sudo setting which is set to true
by default. This means that any dependency will by default run its commands
using sudo:

  dep = Sunshine::Apt.new "libdvdread"
  dep.install! :call => shell

  #=> sudo -H apt-get install libdvdread

This can be changed on the class level:

  shell.sudo = "usr"

  Sunshine::Apt.sudo = nil  # let the shell handle sudo
  dep.install! :call => shell
  
  #=> sudo -H -u usr apt-get install libdvdread

It can also be set on an individual basis:

  dep.install! :call => shell, :sudo => nil


==== Servers

Because of how unix works with servers and ports, it's not uncommon to have to
run start/stop/restart server commands with upgraded permissions. This is true
for Apache and Nginx on ports below 1024. Due to this, servers automatically try
to adjust their permissions to run their commands correctly. Since servers
should run their commands consistantly, the only way to affect their sudo value
is on a server instance basis:

  server = Nginx.new app, :sudo => nil  # let the shell handle sudo

However, the above will most likely cause Nginx's start command to fail if
shell permissions don't allow running root processes.

Note: Servers will ONLY touch permissions if their port is smaller than 1024.


== Sunshine Configuration

Aside from passing the sunshine command options, Sunshine can be configured
both in the deploy script by calling Sunshine.setup and globally in the
~/.sunshine file. The following is a list of supported config keys:

'auto'                -> Automate calls; fail instead of prompting the user;
defaults to false.

'auto_dependencies'   -> Check and install missing deploy dependencies;
defaults to true.

'deploy_env'          -> The default deploy environment to use;
defaults to :development.

'level'               -> Logger's debug level; defaults to 'info'.

'max_deploy_versions' -> The maximum number of deploys to keep on a server;
defaults to 5.

'remote_checkouts'    -> Use remote servers to checkout the codebase;
defaults to false.

'require'             -> Require external ruby libs or gems; defaults to nil.

'trace'               -> Show detailed output messages; defaults to false.

'web_directory'       -> Path to where apps should be deployed to;
defaults to '/var/www'.


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


== Licence

(The MIT License)

Copyright (c) 2010

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
