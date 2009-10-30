module Sunshine

  class Rainbows < Unicorn

    def start_cmd
      "cd #{app.current_path} && rainbows -D -E #{Sunshine.deploy_env} -p #{@port} -c #{@config_file_path}"
    end

  end

end
