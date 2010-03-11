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

    Sunshine.setup 'trace'      => true,
                   'deploy_env' => deploy_env


    # View the Sunshine README, scripts in the sunshine/examples
    # directory, or the docs for Sunshine::App for more information on
    # App instantiation.

    @app = Sunshine::App.new "path/to/app_deploy_config.yml"
    # or
    # @app = Sunshine::App.new app_config_hash
  end


  desc "Deploy the app"
  task :deploy => :app do
    @app.deploy do |app|

      # Do deploy-specific stuff here, e.g.
      #
      #   app.run_bundler
      #
      #   unicorn = Sunshine::Unicorn.new app, :port      => 3000,
      #                                        :processes => 8
      #   uncorn.restart

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
    output_status @app
  end


  desc "Run the remote stop script"
  task :stop => :app do
    @app.stop
    output_status @app
  end


  desc "Run the remote restart script"
  task :restart => :app do
    @app.restart
    output_status @app
  end


  desc "Check if the deployed app is running"
  task :status => :app do
    output_status @app
  end


  desc "Get deployed app info"
  task :info => :app do
    puts @app.deploy_details.to_yaml
  end


  desc "Get the health state"
  task :health => :app do
    puts @app.health.status.to_yaml
  end


  namespace :health do

    desc "Get the health state"
    task :check => :app do
      health_status @app
    end


    desc "Turn on health check"
    task :enable => :app do
      @app.health.enable
      health_status @app
    end


    desc "Turn off health check"
    task :disable => :app do
      @app.health.disable
      health_status @app
    end


    desc "Remove health check"
    task :remove => :app do
      @app.health.remove
      health_status @app
    end
  end


  def health_status app
    puts app.health.status.to_yaml
  end

  def output_status app
    puts app.status.to_yaml
  end
end
