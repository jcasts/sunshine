require 'sunshine'
require 'sunshine/presets/atti'

namespace :sunshine do

  desc "Instantiate Sunshine"
  task :app do
    deploy_env = ENV['env'] || ENV['RACK_ENV'] || ENV['RAILS_ENV']
    deploy_env ||= "development"

    Sunshine.setup 'sudo'          => 'nextgen',
                   'web_directory' => '~nextgen',
                   'deploy_env'    => deploy_env

    app_hash = {
      :repo => {
        :type => :svn,
        :url  => "svn://subversion.flight.yellowpages.com/webtools/webservices/envoy/tags/200912.2-WAT-235-release"
      },
      :remote_shells => %w{jcast.np.wc1.yellowpages.com}
    }

    @app = Sunshine::AttiApp.new app_hash
  end


  desc "Deploy the app"
  task :deploy => :app do
    Sunshine.setup 'trace' => true

    @app.deploy do |app|

      rainbows = Sunshine::Rainbows.new(app, :port => 5001)

      nginx = Sunshine::Nginx.new(app, :point_to => rainbows, :port => 5000)
      nginx.log_files :impressions => "#{app.log_path}/impressions.log",
                      :stderr      => "#{app.log_path}/error.log",
                      :stdout      => "#{app.log_path}/access.log"

      app.run_geminstaller

      app.upload_tasks 'app', 'common', 'tpkg'

      rainbows.restart
      nginx.restart
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
    health_status @app
  end


  namespace :health do

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
