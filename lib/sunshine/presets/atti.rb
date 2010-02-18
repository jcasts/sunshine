
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

    def datacenter
      dc_name = @deploy_env.to_s =~ /^prod.*_([a-z0-9]{2,})/ && $1
      dc_name || "np"
    end


    ##
    # Get the name of the db yml file to use based on the deploy_env.

    def db_setup_file secure=false
      secure ? "database.yml" : "database-#{datacenter}.yml.gpg"
    end


    ##
    # Decrypt a file using gpg. Allows options:
    # :output:: str - the path the output file should go to
    # :passphrase:: str - the passphrase gpg should use
    # :servers:: arr - the deploy servers to run the command on

    def gpg_decrypt gpg_file, options={}
      output_file = options[:output] || gpg_file.gsub /\.gpg$/, ''

      passphrase   = options[:passphrase]
      passphrase ||= Sunshine.console.ask("Enter gpg passphrase:") do |q|
        q.echo = false
      end

      passphrase_file = "#{@deploy_path}/tmp/.gpg_passphrase"

      gpg_cmd = "gpg --batch --no-tty --yes --output #{output_file} "+
        "--passphrase-file #{passphrase_file} --decrypt #{gpg_file}"

      d_servers = [*options[:servers]] || @deploy_servers

      d_servers.each do |deploy_server|
        deploy_server.make_file passphrase_file, passphrase
        deploy_server.call "cd #{@checkout_path} && #{gpg_cmd}"
        deploy_server.call "rm -f #{passphrase_file}"
      end
    end
  end
end



