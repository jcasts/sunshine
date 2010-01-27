require 'test/test_helper'

class TestCrontab < Test::Unit::TestCase

  def setup
    @crontab_str = <<-STR
# sunshine crontest:job1:begin
this job should stay
# sunshine crontest:job1:end

# sunshine crontest:job2:begin
this job should be replaced
# sunshine crontest:job2:end

# sunshine crontest:job2:begin
this job should be removed
# sunshine crontest:job2:end
    STR

    @cron = Sunshine::Crontab.new "crontest"
  end

  def test_add
    @cron.add "namespace1", "this is a job"
    @cron.add "namespace1", "another job"
    @cron.add "namespace1", "this is a job"
    @cron.add "namespace2", "this is a job"

    assert_equal ["this is a job", "another job"], @cron.jobs["namespace1"]
    assert_equal ["this is a job"], @cron.jobs["namespace2"]
  end


  def test_build
    @cron.add "job2", "new job2"
    @cron.add "job3", "new job3"

    @cron.build @crontab_str

    assert_cronjob "job1", "this job should stay"
    assert_cronjob "job2", "new job2"
    assert_cronjob "job3", "new job3"

    assert !@crontab_str.include?("this job should be replaced")
    assert !@crontab_str.include?("this job should be removed")
  end


  def test_write!
    ds = mock_deploy_server
    ds.set_mock_response 0, "crontab -l" => [:out, @crontab_str]

    @cron.add "job2", "new job2"
    @cron.add "job3", "new job3"

    @crontab_str = @cron.write! ds

    assert_cronjob "job1", "this job should stay"
    assert_cronjob "job2", "new job2"
    assert_cronjob "job3", "new job3"

    cmd = "echo '#{@crontab_str.gsub(/'/){|s| "'\\''"}}' | crontab"

    assert_ssh_call cmd
  end


  def assert_cronjob namespace, job
    assert @crontab_str.include?(cronjob(namespace, job))
  end


  def cronjob namespace, job
<<-STR
# sunshine crontest:#{namespace}:begin
#{job}
# sunshine crontest:#{namespace}:end
STR
  end
end
