namespace :sunshine do

  ##
  # If using Rails, have the environment available by updating :app task to:
  #   task :app => :environment do
  #     ...
  #   end

  desc "Instantiate app"
  task :app do
    require 'sunshine'

    # By default, Sunshine will deploy with env set from (in order):
    # ENV['DEPLOY_ENV'] || ENV['env'] || ENV['RACK_ENV'] || ENV['RAILS_ENV']
    #
    # If using Rails, you may want to setup Sunshine with the same environment:
    # Sunshine.setup 'deploy_env' => Rails.environment


    # View the Sunshine README, scripts in the sunshine/examples
    # directory, or the docs for Sunshine::App for more information on
    # App instantiation.

    @app = Sunshine::App.new "path/to/app_deploy_config.yml"
    # or
    # @app = Sunshine::App.new app_config_hash
  end


  ##
  # Put your deploy-specific logic in the deploy task...

  desc "Deploy the app"
  task :deploy => :app do
    Sunshine.setup 'trace' => true

    @app.deploy do |app|

      # Do deploy-specific stuff here, e.g.
      #
      #   app.run_bundler
      #
      #   unicorn = Sunshine::Unicorn.new app, :port      => 3000,
      #                                        :processes => 8
      #   unicorn.setup

    end
  end


  ##
  # Server setup logic that doesn't need to be run on every deploy
  # can be put in the :setup task.
  #
  # Note: By default, Sunshine will attempt to install missing server
  # dependencies that it uses if they are not present (e.g. Nginx, Apache...).
  # If you would like to disable this behavior and handle these dependencies
  # explicitely, add this setup configuration to your :app or :deploy task:
  #   Sunshine.setup 'auto_dependencies' => false
  #
  # If you do so, ensure that the dependency bins are available in $PATH.

  desc "Sets up deploy servers"
  task :setup => :app do
    Sunshine.setup 'trace' => true

    # Setup servers here
    #
    #   @app.with_filter :role => :app do |app|
    #     app.yum_install 'libxml2', 'libxml2-devel'
    #     app.gem_install 'mechanize'
    #   end
    #
    #   @app.with_filter :role => :db do |app|
    #     app.yum_install 'sqlite'
    #     app.gem_install 'sqlite3'
    #   end
    #
    # If you're not able to add your public key to remote servers,
    # you can setup your tasks to use the App#with_session method
    # to avoid having to login multiple times:
    #
    #   @app.with_session do
    #     @app.with_filter :role => :app do |app|
    #       app.yum_install 'libxml2', 'libxml2-devel'
    #       app.gem_install 'mechanize'
    #     end
    #     ...
    #   end
  end


  # Post-deploy control tasks:

  desc "Run the remote start script"
  task :start => :app do
    @app.start
    puts @app.status.to_yaml
  end


  desc "Run the remote stop script"
  task :stop => :app do
    @app.stop
    puts @app.status.to_yaml
  end


  desc "Run the remote restart script"
  task :restart => :app do
    @app.restart
    puts @app.status.to_yaml
  end


  desc "Check if the deployed app is running"
  task :status => :app do
    puts @app.status.to_yaml
  end


  desc "Get deployed app info"
  task :info => :app do
    puts @app.deploy_details.to_yaml
  end
end
