require 'cgi'

module MockObject

  ##
  # Setup a method mock

  def mock method, options={}, &block
    mock_key = mock_key_for method, options
    method_mocks[mock_key] = block_given? ? block : options[:return]
  end


  ##
  # Get the value a mocked method was setup to return

  def method_mock_return mock_key
    return_val = method_mocks[mock_key] rescue method_mocks[[mock_key.first]]
    if Proc === return_val
      args = mock_key[1..-1]
      return_val.call(*args)
    else
      return_val
    end
  end


  ##
  # Create a mock key based on :method, :args => [args_passed_to_method]

  def mock_key_for method, options={}
    mock_key = [method.to_s]
    mock_key.concat [*options[:args]] if options.has_key?(:args)
    mock_key
  end


  ##
  # Check if a method was called. Supports options:
  # :exactly:: num - exact number of times the method should have been called
  # :count:: num   - minimum number of times the method should have been called
  # Defaults to :count => 1

  def method_called? method, options={}
    target_count = options[:count] || options[:exactly] || 1

    count = method_call_count method, options

    options[:exactly] ? count == target_count : count >= target_count
  end


  ##
  # Count the number of times a method was called:
  #  obj.method_call_count :my_method, :args => [1,2,3]

  def method_call_count method, options={}
    count = 0

    mock_def_arr = mock_key_for method, options

    each_mock_key_matching(mock_def_arr) do |mock_key|
      count = count + method_log[mock_key]
    end

    count
  end


  ##
  # Do something with every instance of a mock key.
  # Used to retrieve all lowest common denominators of method calls:
  #
  #   each_mock_key_matching [:my_method] do |mock_key|
  #     puts mock_key.inspect
  #   end
  #
  #   # Outputs #
  #   [:my_method, 1, 2, 3]
  #   [:my_method, 1, 2]
  #   [:my_method, 1]
  #   [:my_method]

  def each_mock_key_matching mock_key
    index = mock_key.length - 1

    method_log.keys.each do |key|
      yield(key) if block_given? && key[0..index] == mock_key
    end
  end


  def method_mocks
    @method_mocks ||= Hash.new do |h, k|
      raise "Mock for #{k.inspect} does not exist."
    end
  end


  def method_log
    @method_log ||= Hash.new(0)
  end


  ##
  # Hook into the object

  def self.included base
    hook_instance_methods base
  end


  def self.extended base
    hook_instance_methods base, true
  end


  def self.hook_instance_methods base, instance=false
    unhook_instance_methods base, instance

    eval_each_method_of(base, instance) do |m|
      m_def = m =~ /[^\]]=$/ ? "args" : "*args, &block"
      new_m = escape_unholy_method_name "hooked_#{m}"
      %{
        alias #{new_m} #{m}
        undef #{m}

        def #{m}(#{m_def})
          mock_key = mock_key_for '#{m}', :args => args

          count = method_log[mock_key]
          method_log[mock_key] = count.next
          
          method_mock_return(mock_key) rescue self.send(:#{new_m}, #{m_def})
        end
      }
    end
  end


  def self.unhook_instance_methods base, instance=false
    eval_each_method_of(base, instance) do |m|
       new_m = escape_unholy_method_name "hooked_#{m}"
       #puts m + " -> " + new_m
      %{
        m = '#{new_m}'.to_sym
        defined = method_defined?(m) rescue self.class.method_defined?(m)

        if defined
          undef #{m}
          alias #{m} #{new_m}
        end
      }
    end
  end


  def self.escape_unholy_method_name name
    CGI.escape(name).gsub('%','').gsub('-','MNS')
  end


  def self.eval_each_method_of base, instance=false, &block
    eval_method, affect_methods = if instance
      [:instance_eval, base.methods]
    else
      [:class_eval, base.instance_methods]
    end

    banned_methods = self.instance_methods
    banned_methods.concat Object.instance_methods

    affect_methods.sort.each do |m|
      next if banned_methods.include?(m)
      #puts m
      base.send eval_method, block.call(m)
    end
  end
end
