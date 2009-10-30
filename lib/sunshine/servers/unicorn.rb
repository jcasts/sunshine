module Sunshine

  class Unicorn < Server

    def start_cmd
      "cd #{app.current_path} && unicorn -D -E #{Sunshine.deploy_env} -p #{@port} -c #{@config_file_path}"
    end

    def stop_cmd
      "(test -f #{@pid_file} && kill -QUIT `cat #{@pid_file}`) || true; sleep 2; rm -f #{@pid_file}"
    end

  end

end
