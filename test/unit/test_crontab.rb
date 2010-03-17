require 'test/test_helper'

class TestCrontab < Test::Unit::TestCase

  def setup
    @crontab_str = <<-STR
# sunshine crontest:job1:begin
this job should stay
# sunshine crontest:job1:end

# sunshine crontest:job2:begin
job2 part 1
# sunshine crontest:job2:end

# sunshine otherapp:blah:begin
otherapp blah job
# sunshine otherapp:blah:end

# sunshine crontest:job2:begin
job2 part 2
# sunshine crontest:job2:end

# sunshine otherapp:job1:begin
job for otherapp
# sunshine otherapp:job1:end
    STR

    @shell = mock_remote_shell

    @shell.set_mock_response 0, "crontab -l" => [:out, @crontab_str]
    @cron = Sunshine::Crontab.new "crontest", @shell

    @shell.set_mock_response 0, "crontab -l" => [:out, @crontab_str]
    @othercron = Sunshine::Crontab.new "otherapp", @shell

    @shell.set_mock_response 0, "crontab -l" => [:out, @crontab_str]
  end

  def test_add
    @cron.add "namespace1", "this is a job"
    @cron.add "namespace1", "another job"
    @cron.add "namespace1", "this is a job"
    @cron.add "namespace2", "this is a job"

    assert_equal ["this is a job", "another job"], @cron.jobs["namespace1"]
    assert_equal ["this is a job"], @cron.jobs["namespace2"]
  end


  def test_parse
    jobs = @cron.parse @crontab_str
    assert_equal ["this job should stay"], jobs['job1']
    assert_equal ["job2 part 1", "job2 part 2"], jobs['job2']
    assert jobs['blah'].empty?
  end


  def test_build
    @cron.add "job2", "new job2"
    @cron.add "job3", "new job3"

    @cron.build @crontab_str

    assert_cronjob "job1", "this job should stay"
    assert_cronjob "job2", ["job2 part 1", "job2 part 2", "new job2"]
    assert_cronjob "job3", "new job3"

    assert_cronjob "blah", "otherapp blah job", @othercron
    assert_cronjob "job1", "job for otherapp", @othercron
  end


  def test_delete!
    assert_cronjob "blah", "otherapp blah job", @othercron
    assert_cronjob "job1", "job for otherapp", @othercron

    @crontab_str = @othercron.delete!

    assert !@crontab_str.include?("job for otherapp")
    assert !@crontab_str.include?("otherapp blah job")

    assert_cronjob "job1", "this job should stay"
    assert_cronjob "job2", "job2 part 1"
    assert_cronjob "job2", "job2 part 2"
  end


  def test_write!
    @cron.add "job2", "new job2"
    @cron.add "job3", "new job3"

    @crontab_str = @cron.write!

    assert_cronjob "job1", "this job should stay"
    assert_cronjob "job2", ["job2 part 1", "job2 part 2", "new job2"]
    assert_cronjob "job3", "new job3"

    assert_cronjob "blah", "otherapp blah job", @othercron
    assert_cronjob "job1", "job for otherapp", @othercron

    cmd = "echo '#{@crontab_str.gsub(/'/){|s| "'\\''"}}' | crontab"

    assert_ssh_call cmd
  end


  def test_removed_jobs_write!
    @cron.remove "job1"

    @crontab_str = @cron.write!

    assert !@crontab_str.include?("this job should stay")
    assert_cronjob "job2", ["job2 part 1", "job2 part 2"]

    assert_cronjob "blah", "otherapp blah job", @othercron
    assert_cronjob "job1", "job for otherapp", @othercron

    cmd = "echo '#{@crontab_str.gsub(/'/){|s| "'\\''"}}' | crontab"

    assert_ssh_call cmd
  end


  def assert_cronjob namespace, job, crontab=@cron
    assert @crontab_str.include?(cronjob(namespace, job, crontab))
  end


  def cronjob namespace, job, crontab
<<-STR
# sunshine #{crontab.name}:#{namespace}:begin
#{[*job].join("\n")}
# sunshine #{crontab.name}:#{namespace}:end
STR
  end
end
