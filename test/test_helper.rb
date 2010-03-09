require 'sunshine'
require 'test/unit'

def no_mocks
  ENV['mocks'] == "false"
end

unless no_mocks
  require 'test/mocks/mock_object'
  require 'test/mocks/mock_open4'
end

unless defined? TEST_APP_CONFIG_FILE
  TEST_APP_CONFIG_FILE = "test/fixtures/app_configs/test_app.yml"
end


def mock_app
  Sunshine::App.new(TEST_APP_CONFIG_FILE).extend MockObject
end


def mock_deploy_server host=nil
  host ||= "jcastagna@jcast.np.wc1.yellowpages.com"
  deploy_server = Sunshine::DeployServer.new host

  deploy_server.extend MockOpen4
  deploy_server.extend MockObject

  use_deploy_server deploy_server

  deploy_server.connect
  deploy_server
end


def mock_svn_response url=nil
  url ||= "svn://subversion.flight.yellowpages.com/argo/parity/trunk"

  svn_response = <<-STR
    <?xml version="1.0"?>
    <log>
    <logentry
      revision="786">
    <author>jcastagna</author>
    <date>2010-01-26T01:49:17.372152Z</date>
    <msg>finished testing server.rb</msg>
    </logentry>
    </log>
  STR

  Sunshine::SvnRepo.extend(MockObject) unless
    Sunshine::SvnRepo.is_a?(MockObject)

  Sunshine::SvnRepo.mock :svn_log, :return => svn_response
  Sunshine::SvnRepo.mock :get_svn_url, :return => url
end


def mock_deploy_server_popen4
  return if no_mocks
  Sunshine::DeployServer.class_eval{ include MockOpen4 }
end


def set_mock_response_for obj, code, stream_vals={}, options={}
  case obj
  when Sunshine::App then
    obj.deploy_servers.each do |ds|
      ds.set_mock_response code, stream_vals, options
    end
  when Sunshine::DeployServer then
    obj.set_mock_response code, stream_vals, options
  end
end


def assert_dep_install dep_name
  dep = Sunshine::Dependencies[dep_name]

  assert dep.method_called?(:install!, :args => [{:call => @deploy_server}]),
    "#{dep_name} install was not called."
end


def assert_not_called *args
  assert !@deploy_server.method_called?(:call, :args => [*args]),
    "Command called by #{@deploy_server.host} but should't have:\n #{args[0]}"
end


def assert_server_call *args
  assert @deploy_server.method_called?(:call, :args => [*args]),
    "Command was not called by #{@deploy_server.host}:\n #{args[0]}"
end


def assert_bash_script name, cmds, check_value
  cmds = cmds.map{|cmd| "(#{cmd})" }
  cmds << "echo true"

  bash = <<-STR
#!/bin/bash
if [ "$1" == "--no-env" ]; then
  #{cmds.flatten.join(" && ")}
else
  #{@app.deploy_path}/env #{@app.deploy_path}/#{name} --no-env
fi
  STR

  assert_equal bash, check_value
end


def assert_ssh_call expected, ds=@deploy_server, options={}
  expected = ds.send(:ssh_cmd, expected, options).join(" ")

  error_msg = "No such command in deploy_server log [#{ds.host}]\n#{expected}"
  error_msg << "\n\n#{ds.cmd_log.select{|c| c =~ /^ssh/}.join("\n\n")}"

  assert ds.cmd_log.include?(expected), error_msg
end


def assert_rsync from, to, ds=@deploy_server, sudo=false
  received = ds.cmd_log.last

  rsync_path = if sudo
    path = ds.sudo_cmd('rsync', sudo).join(' ')
    "--rsync-path='#{ path }' "
  end

  rsync_cmd = "rsync -azP #{rsync_path}-e \"ssh #{ds.ssh_flags.join(' ')}\""

  error_msg = "No such command in deploy_server log [#{ds.host}]\n#{rsync_cmd}"
  error_msg << "#{from.inspect} #{to.inspect}"
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


def each_deploy_server app=@app
  app.deploy_servers.each do |ds|
    use_deploy_server ds
    yield(ds) if block_given?
  end
end

Sunshine.setup({}, true)

unless MockObject === Sunshine.console
  Sunshine.console.extend MockObject
  Sunshine.console.mock :<<, :return => nil
  Sunshine.console.mock :write, :return => nil
end

unless MockObject === Settler::Dependency
  Settler::Dependency.send(:include, MockObject)
end
