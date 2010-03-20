require 'sunshine'

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
      :remote_shells => %w{jcastagna@jcast.np.wc1.yellowpages.com}
    }

    @app = Sunshine::App.new app_hash
    @app.add_shell_paths '/home/ypc/sbin'
  end


  desc "Deploy the app"
  task :deploy => :app do
    Sunshine.setup 'trace' => true

    @app.deploy do |app|

      rainbows = Sunshine::Rainbows.new(app, :port => 5001)

      nginx = Sunshine::Nginx.new(app, :point_to => rainbows, :port => 5000)

      app.run_geminstaller

      rainbows.setup
      nginx.setup
    end

    @app.start :force => true
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
