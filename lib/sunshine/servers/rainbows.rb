module Sunshine

  class Rainbows < Unicorn

    def start_cmd
      "cd #{@app.current_path} && #{@bin} -D -E #{@app.deploy_env} -p #{@port} -c #{self.config_file_path}"
    end

  end

end
