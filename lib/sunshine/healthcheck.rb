module Sunshine

  # Future: Change the way healthcheck is done, instead of checking the existance of some random files.
  class Healthcheck

    def initialize(app)
      @app = app
      @hc_file = "#{@app.shared_path}/health.txt"
      @hc_disabled_file = "#{@app.shared_path}/health.disabled"
    end

    def status
      stat = {}
      @app.deploy_servers.each do |ds|
        stat[ds.host] = {}
        stat[ds.host] = :ok and next if server_file_exists? ds, @hc_file
        stat[ds.host] = :disabled and next if server_file_exists?(ds, @hc_disabled_file)
        stat[ds.host] = :down
      end
      stat
    end

    def enable!
      Sunshine.logger.info :healthcheck, "Enabling healthcheck" do
        @app.deploy_servers.run "test -f #{@hc_disabled_file} && rm -f #{@hc_disabled_file}"
        @app.deploy_servers.run "touch #{@hc_file}"
      end
    end

    def disable!
      Sunshine.logger.info :healthcheck, "Disabling healthcheck" do
        @app.deploy_servers.run "touch #{@hc_disabled_file} && rm -f#{@hc_file}"
      end
    end

    def remove!
      Sunshine.logger.info :healthcheck, "Removing healthcheck" do
        @app.deploy_servers.run "test -f #{@hc_disabled_file} && rm -f #{@hc_disabled_file};\
          test -f #{@hc_file} && rm -f #{@hc_file}"
      end
    end

    private

    def server_file_exists?(deploy_server, file)
      "true" == deploy_server.run("(test -f #{file} && echo 'true') || echo 'false'")
    end

  end

end
