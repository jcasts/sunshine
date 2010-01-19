module Sunshine

  ##
  # Simple server wrapper for Rainbows setup and control.

  class Rainbows < Unicorn

    attr_reader :concurrency

    ##
    # Assign and/or use a concurrency model. Supports all Rainbows concurrency
    # models; defaults to :ThreadSpawn
    # Allows options:
    # :model:: :ConcurrModel - the concurrency model rainbows should use.
    # :connections:: int - the number of worker connections to use.
    # :timeout:: int - the keepalive timeout. zero disables keepalives.

    def use_concurrency(options={})
      @concurrency ||= {:model => :ThreadSpawn}
      @concurrency.merge!(options)
    end
  end
end
