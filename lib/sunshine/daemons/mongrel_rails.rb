module Sunshine

  ##
  # Simple wrapper around mongrel setup and commands. For clustering,
  # look at using Sunshine's ServerCluster method, e.g.:
  #   MongrelRails.new_cluster 10, app, :port => 5000
  #
  # Note: This is a rails-only server, implemented for compatibility
  # with older non-rack rails applications. Consider upgrading your
  # application to run on rack and/or thin.
  #
  # Note: Mongrel only supports a single log file.
  # The default stdout file is used.

  class MongrelRails < Server

    def initialize app, options={}
      super

      @dep_name = options[:dep_name] || "mongrel"

      @supports_rack      = false
      @supports_passenger = false
    end


    def start_cmd
      "cd #{@app.current_path} && mongrel_rails start "+
        "-C #{self.config_file_path}"
    end
  end
end
