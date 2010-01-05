require 'sunshine'
require 'tmpdir'
require 'test/unit'

TMP_DIR = File.join Dir.tmpdir, "test_sunshine_#{$$}"

unless ENV['mocks'] == "false"
  require 'test/mocks/mock_open4'
  require 'test/mocks/mock_repo'
  require 'test/mocks/mock_console'

  Sunshine::DeployServer.class_eval{ include MockOpen4 }
end

TEST_APP_CONFIG_FILE = "test/fixtures/app_configs/test_app.yml"



