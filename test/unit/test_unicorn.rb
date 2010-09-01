require 'test/test_helper'

class TestUnicorn < Test::Unit::TestCase

  def setup
    @app = Sunshine::App.new TEST_APP_CONFIG_FILE
    @server = Sunshine::Unicorn.new @app
  end

  def test_start_cmd
    cmd = "cd #{@app.current_path} && #{@server.bin} -D -E"+
      " #{@app.deploy_env} -p #{@server.port} -c #{@server.config_file_path};"

    assert_equal cmd, @server.start_cmd
  end

  def test_stop_cmd
    cmd = "test -f #{@server.pid} && kill -QUIT $(cat #{@server.pid})"+
      " || echo 'No #{@server.name} process to stop for #{@app.name}';"+
      "sleep 2; rm -f #{@server.pid};"
  end
end
