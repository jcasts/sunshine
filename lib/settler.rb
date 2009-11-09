require 'open3'

class Settler

  require 'settler/dependency'
  require 'settler/gem'

  class << self

    def dependencies
      @dependencies ||= {}
    end

    def [](key)
      (@dependencies ||= {})[key]
    end

    def install(*deps)
      options = Hash === deps.last ? deps.delete_at(deps.length - 1) : {}
      deps.each{|dep| dependencies[dep].install! options }
    end

    def uninstall(*deps)
      options = Hash === deps.last ? deps.delete_at(deps.length - 1) : {}
      deps.each{|dep| dependencies[dep].uninstall! options }
    end

  end

end
