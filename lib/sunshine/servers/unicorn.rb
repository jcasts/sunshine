module Sunshine

  class Unicorn < Server

    def start_cmd
      "cd #{@app.current_path} && #{@bin} -D -E"+
        " #{@app.deploy_env} -p #{@port} -c #{self.config_file_path};"
    end

    def stop_cmd
      cmd = "test -f #{@pid} && kill -QUIT $(cat #{@pid})"+
        " || echo 'No #{@name} process to stop for #{@app.name}';"
      cmd << "sleep 2; rm -f #{@pid}; "
      #cmd << "pkill -9 -f #{@app.current_path}/.*/#{File.basename(@pid)}"
    end

  end

end
