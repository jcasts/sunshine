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

    @cron = Sunshine::Crontab.new "crontest", @shell

    @othercron = Sunshine::Crontab.new "otherapp", @shell

    @shell.set_mock_response 0, "crontab -l" => [:out, @crontab_str]
  end


  def test_parse
    jobs = @cron.parse @crontab_str
    assert_equal ["this job should stay"], jobs['job1']
    assert_equal ["job2 part 1","job2 part 2"], jobs['job2']
    assert jobs['blah'].empty?
  end


  def test_build
    @cron.jobs["job2"] << "new job2"
    @cron.jobs["job3"] = "new job3"

    @cron.build @crontab_str

    assert_cronjob "job1", "this job should stay"
    assert_cronjob "job2", "job2 part 1\njob2 part 2\nnew job2"
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
    @cron.jobs["job2"] << "new job2"
    @cron.jobs["job3"] = "new job3"
    @cron.jobs["invalid"] = nil

    @shell.set_mock_response 0, "crontab -l" => [:out, @crontab_str]

    @crontab_str = @cron.write!

    assert_cronjob "job1", "this job should stay"
    assert_cronjob "job2", "job2 part 1\njob2 part 2\nnew job2"
    assert_cronjob "job3", "new job3"
    assert_not_cronjob "invalid"

    assert_cronjob "blah", "otherapp blah job", @othercron
    assert_cronjob "job1", "job for otherapp", @othercron

    cmd = "echo '#{@crontab_str.gsub(/'/){|s| "'\\''"}}' | crontab"

    assert_ssh_call cmd
  end


  def test_deleted_jobs_write!
    @cron.jobs.delete "job1"

    @shell.set_mock_response 0, "crontab -l" => [:out, @crontab_str]

    @crontab_str = @cron.write!

    assert !@crontab_str.include?("this job should stay")
    assert_cronjob "job2", "job2 part 1\njob2 part 2"

    assert_cronjob "blah", "otherapp blah job", @othercron
    assert_cronjob "job1", "job for otherapp", @othercron

    cmd = "echo '#{@crontab_str.gsub(/'/){|s| "'\\''"}}' | crontab"

    assert_ssh_call cmd
  end


  def assert_cronjob namespace, job, crontab=@cron
    assert @crontab_str.include?(cronjob(namespace, job, crontab))
  end


  def assert_not_cronjob namespace, crontab=@cron
    job = cronjob(namespace, [], crontab).split("\n")
    assert !@crontab_str.include?(job[0])
  end


  def cronjob namespace, job, crontab
    job = job.join("\n") if Array === job

<<-STR
# sunshine #{crontab.name}:#{namespace}:begin
#{ job }
# sunshine #{crontab.name}:#{namespace}:end
STR
  end
end
