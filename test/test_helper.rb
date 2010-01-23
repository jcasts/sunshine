require 'sunshine'
require 'test/unit'

def no_mocks
  ENV['mocks'] == "false"
end

unless no_mocks
  require 'test/mocks/mock_object'
  require 'test/mocks/mock_open4'
  require 'test/mocks/mock_repo'
  require 'test/mocks/mock_console'
end

unless defined? TEST_APP_CONFIG_FILE
  TEST_APP_CONFIG_FILE = "test/fixtures/app_configs/test_app.yml"
end


def mock_deploy_server_popen4
  return if no_mocks
  Sunshine::DeployServer.class_eval{ include MockOpen4 }
end


def set_mock_response_for obj, code, stream_vals={}
  case obj
  when Sunshine::App then
    obj.deploy_servers.each{|ds| ds.set_mock_response code, stream_vals}
  when Sunshine::DeployServer then
    obj.set_mock_response code, stream_vals
  end
end


def assert_ssh_call expected, ds=@deploy_server
  expected = ds.send(:ssh_cmd, expected).join(" ")

  error_msg = "No such command in deploy_server log [#{ds.host}]\n#{expected}"
  error_msg << "\n\n#{ds.cmd_log.select{|c| c =~ /^ssh/}.join("\n\n")}"

  assert ds.cmd_log.include?(expected), error_msg
end


def assert_rsync from, to, ds=@deploy_server
  received = ds.cmd_log.last
  rsync_cmd = "rsync -azP -e \"ssh #{ds.ssh_flags.join(' ')}\""

  error_msg = "No such command in deploy_server log [#{ds.host}]\n#{rsync_cmd}"
  error_msg << "#{from} #{to}"
  error_msg << "\n\n#{ds.cmd_log.select{|c| c =~ /^rsync/}.join("\n\n")}"

  if Regexp === from
    found = ds.cmd_log.select do |cmd|

      cmd_from = cmd.split(" ")[-2]
      cmd_to   = cmd.split(" ").last

      cmd_from =~ from && cmd_to == to && cmd.index(rsync_cmd) == 0
    end

    assert !found.empty?, error_msg
  else
    expected = "#{rsync_cmd} #{from} #{to}"
    assert ds.cmd_log.include?(expected), error_msg
  end
end

def use_deploy_server deploy_server
  @deploy_server = deploy_server
end

Sunshine.setup

