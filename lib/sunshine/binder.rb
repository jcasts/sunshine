module Sunshine

  ##
  # Create a selective binding. Useful for controlling ERB builds:
  #   binder.set :server_name, "blah.com"
  #   binder.forward :server_method, ...
  #   binder.get_binding

  class Binder

    def initialize target
      @target = target
    end


    ##
    # Set the binding instance variable and accessor method.

    def set key, value=nil, &block
      value ||= block if block_given?

      instance_variable_set("@#{key}", value)

      eval_str = <<-STR
        undef #{key} if defined?(#{key})
        def #{key}(*args)
          if Proc === @#{key}
            @#{key}.call(*args)
          else
            @#{key}
          end
        end
      STR

      instance_eval eval_str, __FILE__, __LINE__ + 1
    end


    ##
    # Takes a hash and assign each hash key/value as an attribute.

    def import_hash hash
      hash.each{|k, v| self.set(k, v)}
    end


    ##
    # Forward a method to the server instance.

    def forward *method_names
      method_names.each do |method_name|
        instance_eval <<-STR, __FILE__, __LINE__ + 1
        undef #{method_name} if defined?(#{method_name})
        def #{method_name}(*args, &block)
          @target.#{method_name}(*args, &block)
        end
        STR
      end
    end


    ##
    # Retrieve the object's binding.

    def get_binding
      binding
    end
  end
end
