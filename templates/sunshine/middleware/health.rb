module Sunshine

  class Health

    ##
    # Default healthcheck request path.

    DEFAULT_REQUEST_PATH = '/_health'


    ##
    # The healthcheck-enabled file.

    HEALTHCHECK_FILE = 'health.enabled'


    ##
    # Creates a new SunshineHealth middleware. Supported options are:
    # :uri_path::    The path that healthcheck will be used on.
    # :health_file:: The file to check for health.

    def initialize app, options={}
      @app              = app
      @uri_path         = options[:uri_path]    || DEFAULT_REQUEST_PATH
      @healthcheck_file = options[:health_file] || HEALTHCHECK_FILE
    end


    def call env
      check_health?(env) ? health_response : @app.call(env)
    end


    ##
    # Given the rack env, do we need to perform a health check?

    def check_health? env
      env['PATH_INFO'] == @uri_path
    end


    ##
    # Check if healthcheck is enabled.

    def health_enabled?
      File.file? @healthcheck_file
    end


    ##
    # Get a rack response for the current health status.

    def health_response
      status, body = health_enabled? ? [200, "OK"] : [404, "404"]
      [status, {'Content-Type' => 'text/html'}, body]
    end
  end
end
