require 'sunshine'

namespace :sunshine do

  ##
  # If using rails, have rails information available by updating :app task to:
  #   task :app => :environment do
  #     ...
  #   end

  desc "Instantiate Sunshine"
  task :app do
    deploy_env = ENV['env'] || ENV['RACK_ENV'] || ENV['RAILS_ENV']

    Sunshine.setup 'deploy_env' => ( deploy_env || "development" )


    # View the Sunshine README, scripts in the sunshine/examples
    # directory, or the docs for Sunshine::App for more information on
    # App instantiation.

    @app = Sunshine::App.new "path/to/app_deploy_config.yml"
    # or
    # @app = Sunshine::App.new app_config_hash
  end


  desc "Deploy the app"
  task :deploy => :app do
    Sunshine.setup 'trace' => true

    # If you're not able to add your public key to remote servers,
    # you can setup your tasks to use the App#with_session method
    # to avoid having to login multiple times:
    #
    #   @app.with_session do
    #     @app.deploy do |app|
    #       ...
    #     end
    #
    #     # Do more things with @app here...
    #
    #   end

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


  # Post-deploy control tasks:

  desc "Run db:migrate on remote :db servers"
  task :db_migrate => :app do
    @app.rake 'db:migrate', :role => :db
  end


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


  desc "Get the health state"
  task :health => :app do
    puts @app.health.to_yaml
  end


  namespace :health do

    desc "Turn on health check"
    task :enable => :app do
      puts @app.health(:enable).to_yaml
    end


    desc "Turn off health check"
    task :disable => :app do
      puts @app.health(:disable).to_yaml
    end


    desc "Remove health check"
    task :remove => :app do
      puts @app.health(:remove).to_yaml
    end
  end
end
