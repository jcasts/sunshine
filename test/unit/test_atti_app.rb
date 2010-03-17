require 'test/test_helper'
require 'sunshine/presets/atti'

class TestAttiApp < Test::Unit::TestCase

  def setup
    svn_url = "svn://subversion.flight.yellowpages.com/argo/parity/trunk"

    @config = {:name => "parity",
               :repo => {:type => "svn", :url => svn_url},
               :remote_shells => mock_remote_shell,
               :deploy_path => "/usr/local/nextgen/parity"}


    @app = Sunshine::AttiApp.new @config

    @tmpdir = File.join Dir.tmpdir, "test_sunshine_#{$$}"

    mock_svn_response @app.repo.url
  end


  def test_setup_logrotate
    crontab = @app.server_apps.first.crontab.extend MockObject

    config_path = "#{@app.checkout_path}/config"

    cronjob = "00 * * * * /usr/sbin/logrotate"+
      " --state /dev/null --force #{@app.current_path}/config/logrotate.conf"

    set_mock_response_for @app, 0,
      'crontab -l' => [:out, " "]

    @app.setup_logrotate

    assert crontab.method_called?(:add, :args => "logrotate")
    assert crontab.method_called?(:write!, :exactly => 1)

    new_crontab = crontab.build

    assert_equal [cronjob], crontab.jobs["logrotate"]

    each_remote_shell do |ds|
      assert_ssh_call "echo '#{new_crontab}' | crontab"
      assert_ssh_call "mkdir -p #{config_path} #{@app.log_path}/rotate"
      assert_rsync(/logrotate/, "#{ds.host}:#{config_path}/logrotate.conf")
    end
  end
end
