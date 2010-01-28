module Sunshine

  ##
  # Instantiated per deploy server and used to pass bindings to the config's
  # ERB build method:
  #   binder.set :server_name, "blah.com"
  #   binder.forward :server_method, ...
  #   binder.get_binding

  class Binder

    def initialize target
      @target = target
    end


    ##
    # Set the binding instance variable and accessor method.

    def set name, value
      instance_variable_set("@#{name}", value)

      instance_eval <<-STR
        undef #{name} if defined?(#{name})
        def #{name}; @#{name};end
      STR
    end


    ##
    # Forward a method to the server instance.

    def forward *method_names
      method_names.each do |method_name|
        instance_eval <<-STR
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
