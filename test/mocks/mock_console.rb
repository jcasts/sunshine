class MockConsole

  def initialize(*args)
  end

  def hidden_prompt(*args)
  end

  def prompt(*args)
  end

  def write(*args)
  end

  def <<(*args)
  end

  def close(*args)
  end

  def ask(*args, &block)
    "some input"
  end

end

Sunshine.send(:remove_const, :Console)
Sunshine::Console = MockConsole
