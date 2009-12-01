
class MockSSH

  def self.start(*args, &block)
    new
  end

  attr_reader :scp

  def initialize
    @connected = true
    @scp = MockSCP.new
  end

  def close
    @connected = false
  end

  def closed?
    !@connected
  end

  def exec!(*args, &block)
    return_val = case args[0]
    when "uname -s"
      [:stdout, "linux\n"]
    when "cat sunshine_test_file"
      [:stdout, "test data"]
    when "echo 'this is an error' 1>&2"
      [:stderr, "this is an error\n"]
    when "echo 'line1'; echo 'line2'"
      [:stdout, "line1\nline2\n"]
    else
      [:stdout, "true\n"]
    end
    yield("mock_channel", return_val[0], return_val[1]) if block_given?
    return_val[1]
  end

end


class MockSCP

  def upload!(*args, &block)
    true
  end

  def download!(*args, &block)
    FileUtils.mkdir_p "sunshine_test"
    File.open("sunshine_test/test_upload", "w+"){|f| f.write "blah"}
    true
  end

end


Net::SSH = MockSSH
Net::SCP = MockSCP
