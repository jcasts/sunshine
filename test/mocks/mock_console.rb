class MockConsole < Sunshine::Console

  def write(*args)
  end

  def <<(*args)
  end

  def ask(*args, &block)
    "some input"
  end

end

Sunshine.send(:remove_const, :Console)
Sunshine::Console = MockConsole
