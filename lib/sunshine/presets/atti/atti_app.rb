module Sunshine

  class AttiApp < App

    def initialize(*args)
      super

      prefer_pkg_manager [Settler::Tpkg, Settler::Yum]

      add_shell_paths "/home/t/bin", "/home/ypc/sbin"
    end


    ##
    # Get the 2-3 letter representation of the datacenter to use
    # based on the deploy_env.

    def datacenter env=@deploy_env
      dc_name = env.to_s =~ /^prod.*_([a-z0-9]{2,})/ && $1
      dc_name || "np"
    end


    ##
    # Get the name of the db yml file to use based on the deploy_env.

    def db_setup_file secure=false
      secure ? "config/database.yml" : "config/database-#{datacenter}.yml.gpg"
    end


    ##
    # Gpg decrypt the database yml file. Allows all DeployServerDispatcher#find
    # and AttiApp#gpg_decrypt options, plus:
    # :file:: str - the local path to the database yml

    def decrypt_db_yml options={}
      gpg_file = options[:file] || db_setup_file(true)
      gpg_decrypt gpg_file, options
    end


    ##
    # Upload logrotate config file, install dependencies,
    # and add to the crontab.

    def setup_logrotate options=nil
      @crontab.add "logrotate",
        "00 * * * * /usr/sbin/logrotate"+
        " --state /dev/null --force #{@current_path}/config/logrotate.conf"


      config_path    = "#{@checkout_path}/config"
      logrotate_path = "#{config_path}/logrotate.conf"

      with_server_apps options, :msg => "Setting up logrotate" do |server_app|
        logrotate_conf =
            build_erb("templates/logrotate/logrotate.conf.erb", binding)

        server_app.install_deps 'logrotate', 'mogwai_logpush'

        server_app.call "mkdir -p #{config_path} #{@log_path}/rotate"
        server_app.make_file logrotate_path, logrotate_conf

        @crontab.write! server_app
      end

    rescue => e
      Sunshine.logger.warn :app,
        "#{e.class} (non-critical): #{e.message}. Failed setting up logrotate."+
        "Log files may not be rotated or pushed to Mogwai!"
    end
  end
end

