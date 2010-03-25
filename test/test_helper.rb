require 'sunshine'
require 'test/unit'

require 'helper_methods'
include HelperMethods


require 'test/mocks/mock_object'
require 'test/mocks/mock_open4'

unless defined? TEST_APP_CONFIG_FILE
  TEST_APP_CONFIG_FILE = "test/fixtures/app_configs/test_app.yml"
end


Sunshine.setup({}, true)

unless MockObject === Sunshine.shell
  Sunshine.shell.extend MockObject
  Sunshine.shell.mock :<<, :return => nil
  Sunshine.shell.mock :write, :return => nil
end

YAML.extend MockObject unless MockObject === YAML

unless Sunshine::Dependency.include? MockObject
  Sunshine::Dependency.send(:include, MockObject)
end
