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
        passenger_root = setup_passenger(server_app.shell) if use_passenger?

        binder.set :passenger_root, passenger_root
        binder.forward :use_passenger?

        yield(server_app, binder) if block_given?
      end
    end


    ##
    # Check if passenger is required to run the application.
    # Returns true if the server's target is a Sunshine::App

    def use_passenger?
      @target.is_a?(Sunshine::App)
    end


    private

    def setup_passenger shell
      Dependencies.install 'passenger', :call => shell
      str = shell.call "gem list passenger -d"
      version = str.match(/passenger\s\((.*)\)$/)[1]
      gempath = str.match(/Installed\sat:\s(.*)$/)[1]
      File.join(gempath, "gems/passenger-#{version}")
    end
  end
end
