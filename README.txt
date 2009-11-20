= Sunshine

== Description

Sunshine is a gem that sits on top of deploy frameworks (such as Capistrano or Vlad) and provides a light, consistant api for application deployment by allowing redundant or default configuration to be centrally (and remotely) managed.


== Setup

Once Sunshine is installed it will need to know which remote servers to pull default configurations from:

  gem install sunshine
  gem sunshine add_source server1.com [more ...]

Sunshine default sources can be removed as follows:

  gem sunshine remove_source server1.com [more ...]

If you do not want to add a specific source to your global sunshine server list, you can specify a source directly in your deploy file by passing a url to the sunshine method:

  Sunshine::App.new(:config => "server1.com") do |app|
    # ... deploy script ... #
  end


== Deploy Scripts

Once deploy defaults are set, writing a Sunshine config script is easy:

  Sunshine::App.new do |app|

    app.deploy!

    app_server = Sunshine::RainbowsServer.new(app)
    app_server.start!

    Sunshine::NginxServer.new(app, :point_to => app_server).start!
    Sunshine::LogRotateCron.new(app).launch!
    Sunshine::MemcacheServer.new(app).start!

  end

The passed 'app' argument should have all the information needed to build app-related objects such as servers or cron tasks. If not all the information is present you will be prompted to either enter it at runtime or add it to your script.

By default, Sunshine will look for .svn or a .git in your current directory and infer the application name and repository that you would like to deploy. However, since Sunshine allows for full remote configuration, the Sunshine deploy script can be run without the need to checkout the application's codebase. In this case, the repo and/or app name can be defined explicitly:

  Sunshine::App.new(:name => "my_app", :svn => "http://some_repo/my_app/tags/release") do |app|
    # ... deploy script ... #
  end

The deploy method can also optionally take arguments if the app config doesn't specify where to deploy to based on the passed environment:

  Sunshine::App.new do |app|

    app.deploy!("user@server2.com", "user@server3.com")
    Sunshine::RainbowsServer.new(app).start!

  end

