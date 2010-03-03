require 'test/test_helper'
require 'sunshine/presets/atti'

class TestAttiApp < Test::Unit::TestCase

  def setup
    mock_deploy_server_popen4
    svn_url = "svn://subversion.flight.yellowpages.com/argo/parity/trunk"

    @config = {:name => "parity",
               :repo => {:type => "svn", :url => svn_url},
               :deploy_servers => ["jcastagna@jcast.np.wc1.yellowpages.com"],
               :deploy_path => "/usr/local/nextgen/parity"}

    @app = Sunshine::AttiApp.new @config

    @tmpdir = File.join Dir.tmpdir, "test_sunshine_#{$$}"

    mock_svn_response @app.repo.url
  end


  def test_setup_logrotate
    @app.crontab.extend MockObject

    config_path = "#{@app.checkout_path}/config"

    cronjob = "00 * * * * /usr/sbin/logrotate"+
      " --state /dev/null --force #{@app.current_path}/config/logrotate.conf"

    set_mock_response_for @app, 0,
      'crontab -l' => [:out, " "]

    @app.setup_logrotate

    assert @app.crontab.method_called?(:add, :args => "logrotate")
    assert @app.crontab.method_called?(:write!, :exactly => 1)

    new_crontab = @app.crontab.build

    assert_equal [cronjob], @app.crontab.jobs["logrotate"]

    each_deploy_server do |ds|
      assert_ssh_call "echo '#{new_crontab}' | crontab"
      assert_ssh_call "mkdir -p #{config_path} #{@app.log_path}/rotate"
      assert_rsync(/logrotate/, "#{ds.host}:#{config_path}/logrotate.conf")
    end
  end
end
