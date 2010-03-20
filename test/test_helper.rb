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


def mock_remote_shell host=nil
  host ||= "user@some_server.com"
  remote_shell = Sunshine::RemoteShell.new host

  remote_shell.extend MockOpen4
  remote_shell.extend MockObject

  use_remote_shell remote_shell

  remote_shell.connect
  remote_shell
end


def mock_svn_response url=nil
  url ||= "svn://subversion/path/to/my_app/trunk"

  svn_response = <<-STR
    <?xml version="1.0"?>
    <log>
    <logentry
      revision="777">
    <author>user</author>
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


def mock_remote_shell_popen4
  return if no_mocks
  Sunshine::RemoteShell.class_eval{ include MockOpen4 }
end


def set_mock_response_for obj, code, stream_vals={}, options={}
  case obj
  when Sunshine::App then
    obj.each do |sa|
      sa.shell.set_mock_response code, stream_vals, options
    end
  when Sunshine::ServerApp then
    obj.shell.set_mock_response code, stream_vals, options
  when Sunshine::RemoteShell then
    obj.set_mock_response code, stream_vals, options
  end
end


def assert_dep_install dep_name, type=Sunshine::Yum
  prefered = type rescue nil
  args = [{:call => @remote_shell, :prefer => prefered}]

  dep = if Sunshine::Dependency === dep_name
          dep_name
        else
          Sunshine.dependencies.get(dep_name, :prefer => prefered)
        end


  assert dep.method_called?(:install!, :args => args),
    "Dependency '#{dep_name}' install was not called."
end


def assert_not_called *args
  assert !@remote_shell.method_called?(:call, :args => [*args]),
    "Command called by #{@remote_shell.host} but should't have:\n #{args[0]}"
end


def assert_server_call *args
  assert @remote_shell.method_called?(:call, :args => [*args]),
    "Command was not called by #{@remote_shell.host}:\n #{args[0]}"
end


def assert_bash_script name, cmds, check_value
  cmds = cmds.map{|cmd| "(#{cmd})" }
  cmds << "echo true"

  bash = <<-STR
#!/bin/bash
if [ "$1" == "--no-env" ]; then
  #{cmds.flatten.join(" && ")}
else
  #{@app.root_path}/env #{@app.root_path}/#{name} --no-env
fi
  STR

  assert_equal bash, check_value
end


def assert_ssh_call expected, ds=@remote_shell, options={}
  expected = ds.send(:ssh_cmd, expected, options).join(" ")

  error_msg = "No such command in remote_shell log [#{ds.host}]\n#{expected}"
  error_msg << "\n\n#{ds.cmd_log.select{|c| c =~ /^ssh/}.join("\n\n")}"

  assert ds.cmd_log.include?(expected), error_msg
end


def assert_rsync from, to, ds=@remote_shell, sudo=false
  received = ds.cmd_log.last

  rsync_path = if sudo
    path = ds.sudo_cmd('rsync', sudo).join(' ')
    "--rsync-path='#{ path }' "
  end

  rsync_cmd = "rsync -azP #{rsync_path}-e \"ssh #{ds.ssh_flags.join(' ')}\""

  error_msg = "No such command in remote_shell log [#{ds.host}]\n#{rsync_cmd}"
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


def use_remote_shell remote_shell
  @remote_shell = remote_shell
end


def each_remote_shell app=@app
  app.server_apps.each do |sa|
    use_remote_shell sa.shell
    yield(sa.shell) if block_given?
  end
end

Sunshine.setup({}, true)

unless MockObject === Sunshine.shell
  Sunshine.shell.extend MockObject
  Sunshine.shell.mock :<<, :return => nil
  Sunshine.shell.mock :write, :return => nil
end

unless Sunshine::Dependency.include? MockObject
  Sunshine::Dependency.send(:include, MockObject)
end
