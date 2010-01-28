module Sunshine

  ##
  # Simple server wrapper for nginx setup and control.

  class Nginx < Server

    def start_cmd
      sudo = run_sudo? ? "sudo " : ""
      "#{sudo}#{@bin} -c #{self.config_file_path}"
    end


    def stop_cmd
      sudo = run_sudo? ? "sudo " : ""
      cmd = "test -f #{@pid} && #{sudo}kill -QUIT $(cat #{@pid})"+
        " || echo 'No #{@name} process to stop for #{@app.name}';"
      cmd << "sleep 2 ; rm -f #{@pid};"
    end


    def setup
      super do |deploy_server, binder|
        passenger_root = setup_passenger(deploy_server) if use_passenger?

        binder.set :passenger_root, passenger_root
        binder.forward :use_passenger?, :run_sudo?

        yield(deploy_server, binder) if block_given?
      end
    end


    ##
    # Check if passenger is required to run the application.
    # Returns true if the server's target is a Sunshine::App

    def use_passenger?
      @target.is_a?(Sunshine::App)
    end


    ##
    # Check if Nginx should run with sudo.

    def run_sudo?
      @port < 1024
    end

    private

    def setup_passenger deploy_server
      Dependencies.install 'passenger', :call => deploy_server
      str = deploy_server.call "gem list passenger -d"
      version = str.match(/passenger\s\((.*)\)$/)[1]
      gempath = str.match(/Installed\sat:\s(.*)$/)[1]
      File.join(gempath, "gems/passenger-#{version}")
    end
  end
end
