require 'sunshine'
require 'test/unit'


unless ENV['mocks'] == "false"
  require 'test/mocks/mock_open4'
  require 'test/mocks/mock_repo'
  require 'test/mocks/mock_console'

  Sunshine::DeployServer.class_eval{ include MockOpen4 }
end

TEST_APP_CONFIG_FILE = "test/fixtures/app_configs/test_app.yml"


def set_popen4_exitcode code
  Process.set_exit_code code
end


