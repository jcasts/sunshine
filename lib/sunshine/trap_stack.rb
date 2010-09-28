module Sunshine

  ##
  # The TrapStack class handles setting multiple trap blocks as a stack.
  # Once a trap block is triggered, it gets popped off the stack.

  class TrapStack

    ##
    # Adds an INT signal trap with its description on the stack.
    # Returns a trap_item Array.

    def self.add_trap desc=nil, &block
      @trap_stack.unshift [desc, block]
      @trap_stack.first
    end



    ##
    # Call a trap item and display it's message.

    def self.call_trap trap_item
      return unless trap_item

      msg, trap_block = trap_item

      yield msg if block_given?

      trap_block.call
    end


    ##
    # Remove a trap_item from the stack.

    def self.delete_trap trap_item
      @trap_stack.delete trap_item
    end


    ##
    # Sets the default trap.

    def self.trap_signal sig, &block
      @trap_stack = []

      trap sig do
        call_trap @trap_stack.shift, &block
        exit 1
      end
    end
  end
end
