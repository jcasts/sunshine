require 'test/test_helper'

class TestSunshine < Test::Unit::TestCase

  def setup
    mock_yaml_load_file
  end


  def test_default_config
    config = Sunshine::DEFAULT_CONFIG
    Sunshine.setup config

    assert Sunshine::Shell === Sunshine.shell

    assert_equal config['deploy_env'].to_s, Sunshine.deploy_env

    assert_equal !config['auto'], Sunshine.interactive?

    assert Sunshine::Output === Sunshine.logger
    assert_equal Logger::INFO, Sunshine.logger.level

    assert_equal config['max_deploy_versions'], Sunshine.max_deploy_versions

    assert_equal config['trace'], Sunshine.trace?
  end


  def test_find_command
    assert !Sunshine.find_command('st')
    assert_equal 'start', Sunshine.find_command('sta')
    assert_equal 'stop', Sunshine.find_command('sto')
    assert_equal 'add', Sunshine.find_command('a')

    Sunshine::COMMANDS.each do |cmd|
      assert_equal cmd, Sunshine.find_command(cmd)
    end
  end


  def test_exec_run_command
    mock_sunshine_exit
    mock_sunshine_command Sunshine::RunCommand

    Sunshine.run %w{run somefile.rb -l debug -e prod --no-trace}

    assert_command Sunshine::RunCommand, [['somefile.rb'], Sunshine.setup]
  end


  def test_exec_control_commands
    mock_sunshine_exit

    %w{add list restart rm start stop}.each do |name|
      cmd = Sunshine.const_get("#{name.capitalize}Command")

      mock_sunshine_command cmd

      Sunshine.run %w{thing1 thing2 -r remoteserver.com}.unshift(name)

      servers = [Sunshine::RemoteShell.new("remoteserver.com")]

      args = [%w{thing1 thing2}, Sunshine.setup]
      assert_command cmd, args

      assert_equal servers, Sunshine.setup['servers']

      Sunshine.run %w{thing1 thing2 -v}.unshift(name)
      servers = [Sunshine.shell]

      args = [%w{thing1 thing2}, Sunshine.setup]
      assert_command cmd, args

      assert_equal servers, Sunshine.setup['servers']
      assert Sunshine.setup['verbose']
    end
  end


  def test_exec_local_cmd
    mock_sunshine_exit
    mock_sunshine_command Sunshine::RmCommand

    Sunshine.run %w{rm app1 app2}

    dsd = [Sunshine.shell]

    args = [['app1', 'app2'], Sunshine.setup]
    assert_command Sunshine::RmCommand, args

    assert_equal dsd, Sunshine.setup['servers']
  end


  def test_exit
    assert_sunshine_exit_status [true], 0
    assert_sunshine_exit_status [false], 1
    assert_sunshine_exit_status [0, "success!"], 0, "success!"
    assert_sunshine_exit_status [2, "failed!"], 2, "failed!"
  end


  def assert_sunshine_exit_status args, expected_status, msg=""
    args.map!{|a| a.inspect.gsub("\"", "\\\"")}
    args = args.join(",")
    cmd = "ruby -Ilib -e \"require 'sunshine'; Sunshine.exit(#{args})\""

    pid, inn, out, err = Open4.popen4(*cmd)

    status = Process.waitpid2(pid).last

    out_data = out.read
    err_data = err.read

    out.close
    err.close
    inn.close

    assert_equal expected_status, status.exitstatus
    if expected_status == 0
      assert_equal msg, out_data.strip
    else
      assert_equal msg, err_data.strip
    end
  end


  def assert_command cmd, args
    assert cmd.call_log.include?([:exec, args])
  end


  def mock_sunshine_command cmd
    cmd.instance_eval do
      undef exec
      undef call_log if defined?(call_log)

      def call_log
        @call_log ||= []
      end

      def exec *args
        call_log << [:exec, args]
        true
      end
    end
  end

  def mock_sunshine_exit
    Sunshine.instance_eval do
      undef exit

      def exit *args
      end
    end
  end

  def mock_yaml_load_file
    YAML.mock :load_file, :args   => [Sunshine::USER_CONFIG_FILE],
                          :return => Sunshine::DEFAULT_CONFIG
  end

end
