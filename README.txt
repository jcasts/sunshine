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
    :deploy_path => '/usr/local/myapp'
  }

  options[:deploy_servers] = case Sunshine.deploy_env
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
  app.deploy!{|app| Sunshine::Rainbows.new(app).restart }


The yaml file can also be any IO stream whos output will parse to yaml.
This can be ueful for passing the file's DATA and keep all the deploy
information in one place:

    # The following two lines are equivalent:
    app = Sunshine::App.new
    app = Sunshine::App.new Sunshine::DATA

    app.deploy!{|app| Sunshine::Rainbows.new(app).restart }

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

    :deploy_path : /usr/local/app_name

    :deploy_servers :
      - - localhost
        - :roles : web db app

  # Setup for qa environment
  :qa :
    :repo :
      :type : svn
      :url :  svn://subversion/app_name/tags/release_0001
    :deploy_servers :
      - qa1.servers.com
      - qa2.servers.com

  # Prod inherits top level values from :qa
  :prod :
    :inherits : :qa
    :deploy_servers :
      - prod1.servers.com
      - prod2.servers.com

In this example, :prod inherits top level values from :qa (only :repo in this
instance). The :inherits key also supports an array as its value.


== Dependencies

Sunshine has simple, basic dependency support, and relies mostly on preexisting
package manager tools such as yum or rubygems. Sunshine's default dependencies
are defined in the Sunshine::Dependencies class and can be overridden as needed:

  class Sunshine::Dependencies < Settler

    yum 'svn', :pkg => 'subversion'

    yum 'git'

    yum 'nginx'
    ...
  end


Dependencies are uniquely named to the Settler class they belong to, which means
using a different package manager is as simple as redefining the dependencies:

  class Sunshine::Dependencies < Settler

    apt_get 'svn', :pkg => 'subversion'

    apt_get 'git'

    apt_get 'nginx'
    ...
  end


If you would like to define a custom dependency or dependency type, you can do
so by either subclassing Settler::Dependency, or by using the plain
Settler::dependency method and defining custom install, uninstall, and check
bash commands. If passed a String these commands rely on the shell's exit
status; if passed a block it will use the block's return value:

  class Sunshine::Dependencies < Settler

    dependency 'rubygems' do
      requires  'ruby', 'irb'

      install 'yum install -y rubygems && gem update --system --no-ri --no-rdoc'

      uninstall 'yum remove rubygems'

      check do |shell|
        shell.call("gem -v || echo 0").strip >= '1.3.5'
      end
    end
  end


Installing dependencies can be done by calling Settler::install or
directly on the dependency object with Dependency#install!:

  Sunshine::Dependencies.install 'nginx', 'rubygems'

  # Equivalent to:

  Sunshine::Dependencies['nginx'].install!
  Sunshine::Dependencies['rubygems'].install!


By default dependencies are run by Sunshine::console which is a representation
of the local shell. However, Settler dependencies may use any object that
responds to a #call method and takes a single argument, such as
Sunshine::DeployServer objects:

  Sunshine::Dependencies.install 'nginx', :call => deploy_server

  # Equivalent to:

  Sunshine::Dependencies['nginx'].install! :call => deploy_server


Note: To install Sunshine dependencies for a given Sunshine::App object, use
Sunshine::App#install_deps to install on all the app's deploy servers:

    app.install_deps 'nginx', 'rubygems'

    app.install_deps 'postgres', 'pgserver', :role => 'db'


== Deployed Application Control

Sunshine has a variety of commands that allow simple control of
remote or locally deployed applications. These include start, stop, restart
actions to be taken application-wide, as well as querying for the
health and state of the app:

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
