require 'sunshine'
require 'test/unit'

def no_mocks
  ENV['mocks'] == "false"
end

unless no_mocks
  require 'test/mocks/mock_open4'
  require 'test/mocks/mock_repo'
  require 'test/mocks/mock_console'
end

TEST_APP_CONFIG_FILE = "test/fixtures/app_configs/test_app.yml"

def mock_deploy_server_popen4
  return if no_mocks
  Sunshine::DeployServer.class_eval{ include MockOpen4 }
end

def set_popen4_exitcode code
  Process.set_exitcode code
end

Sunshine.setup

