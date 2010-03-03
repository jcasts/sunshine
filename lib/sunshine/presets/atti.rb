
# Dependencies that need fixing for ATTi VMs

class Sunshine::Dependencies < Settler

  tpkg 'git'

  yum 'ruby-devel', :arch => "$(uname -p)"

  yum 'ruby', :pkg => 'ruby-ypc'
end


module Sunshine

  class AttiApp < App

    def initialize(*args)
      super
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
    # Gpg decrypt the database yml file

    def decrypt_db_yml gpg_file=nil
      gpg_file ||= db_setup_file true
      gpg_decrypt gpg_file
    end


    ##
    # Decrypt a file using gpg. Allows options:
    # :output:: str - the path the output file should go to
    # :passphrase:: str - the passphrase gpg should use
    # :servers:: arr - the deploy servers to run the command on

    def gpg_decrypt gpg_file, options={}
      output_file = options[:output] || gpg_file.gsub(/\.gpg$/, '')

      passphrase   = options[:passphrase]
      passphrase ||= Sunshine.console.ask("Enter gpg passphrase:") do |q|
        q.echo = false
      end

      passphrase_file = "#{@deploy_path}/tmp/gpg_passphrase"

      gpg_cmd = "gpg --batch --no-tty --yes --output #{output_file} "+
        "--passphrase-file #{passphrase_file} --decrypt #{gpg_file}"

      d_servers   = [*options[:servers]] if options[:servers]
      d_servers ||= @deploy_servers

      d_servers.each do |deploy_server|
        deploy_server.call "mkdir -p #{File.dirname(passphrase_file)}"
        deploy_server.make_file passphrase_file, passphrase
        deploy_server.call "cd #{@checkout_path} && #{gpg_cmd}"
        deploy_server.call "rm -f #{passphrase_file}"
      end
    end


    ##
    # Upload logrotate config file, install dependencies,
    # and add to the crontab.

    def setup_logrotate(d_servers = @deploy_servers)
      Sunshine.logger.info :app, "Setting up log rotation..." do

        @crontab.add "logrotate",
          "00 * * * * /usr/sbin/logrotate"+
          " --state /dev/null --force #{@current_path}/config/logrotate.conf"

        d_servers.threaded_each do |deploy_server|
          self.install_deps 'logrotate', 'mogwai_logpush',
            :servers => deploy_server

          logrotate_conf =
            build_erb("templates/logrotate/logrotate.conf.erb", binding)

          config_path    = "#{@checkout_path}/config"
          logrotate_path = "#{config_path}/logrotate.conf"

          deploy_server.call "mkdir -p #{config_path} #{@log_path}/rotate"
          deploy_server.make_file logrotate_path, logrotate_conf

          @crontab.write! deploy_server
        end
      end

    rescue => e
      Sunshine.logger.warn :app,
        "#{e.class} (non-critical): #{e.message}. Failed setting up logrotate."+
        "Log files may not be rotated or pushed to Mogwai!"
    end
  end
end



