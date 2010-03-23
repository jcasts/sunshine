module Sunshine

  ##
  # Simple server wrapper for nginx setup and control.

  class Nginx < Server

    def initialize app, options={}
      super
      @sudo ||= @port < 1024
    end


    def start_cmd
      "#{@bin} -c #{self.config_file_path}"
    end


    def stop_cmd
      cmd = "test -f #{@pid} && kill -QUIT $(cat #{@pid})"+
        " || echo 'No #{@name} process to stop for #{@app.name}';"
      cmd << "sleep 2 ; rm -f #{@pid};"
    end


    def setup
      super do |server_app, binder|

        setup_passenger server_app if use_passenger?

        binder.forward :use_passenger?
        binder.set :passenger_root do
          passenger_root server_app.shell
        end

        binder.set :nginx_conf_path do
          nginx_bin = server_app.shell.call "which nginx"
          File.join File.dirname(nginx_bin), '..', 'conf'
        end

        yield(server_app, binder) if block_given?
      end
    end


    ##
    # Check if passenger is required to run the application.
    # Returns true if the server's target is a Sunshine::App

    def use_passenger?
      @target.is_a?(Sunshine::App)
    end


    ##
    # Gets the root of the installer passenger gem.

    def passenger_root shell
      str     = shell.call "gem list passenger -d"
      version = $1 if str =~ /passenger\s\((.*)\)$/
      gempath = $1 if str =~ /Installed\sat:\s(.*)$/

      return unless version && gempath

      File.join(gempath, "gems/passenger-#{version}")
    end


    ##
    # Run passenger installation for nginx

    def setup_passenger server_app
      server_app.install_deps 'passenger'

      server_app.shell.call \
        'passenger-install-nginx-module --auto --auto-download',
                                        :sudo => true do |stream, data, inn|

        if data =~ /Please specify a prefix directory \[(.*)\]:/

          dir = if Sunshine.interactive?
                  server_app.shell.ask \
                    "Where do you want to install Nginx [#{$1}]?"
                else
                  $1
                end

          dir = $1 if dir.strip.empty?
          inn.puts dir

          required_dirs = [
            File.join(dir, 'fastcgi_temp'),
            File.join(dir, 'proxy_temp')
          ]

          server_app.shell.call \
            "mkdir -p #{required_dirs.join(" ")}", :sudo => true

          error_log = File.join(dir, "logs/error.log")

          server_app.shell.call \
            "touch #{error_log} && chmod a+rw #{error_log}", :sudo => true

          server_app.add_shell_paths File.join(dir, 'sbin')
        end
      end
    end
  end
end
