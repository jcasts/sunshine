require 'sunshine'
require 'test/unit'

unless ENV['mocks'] == "false"
  require 'test/mocks/mock_ssh'
  require 'test/mocks/mock_repo'
end

TEST_APP_CONFIG_FILE = "test/fixtures/app_configs/test_app.yml"



