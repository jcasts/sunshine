require 'open3'

class Settler

  require 'settler/dependency'
  require 'settler/yum'
  require 'settler/gem'
  require 'settler/atti_tpkg'

  class << self

    ##
    # Hash of 'name' => object dependencies
    def dependencies
      @dependencies ||= {}
    end

    ##
    # Returns a single dependency by name:
    #   Settler['name'] #=> object
    def [](key)
      (@dependencies ||= {})[key]
    end

    ##
    # Checks for the existance of a dependency by name
    def exist?(key)
      self.dependencies.has_key?(key)
    end

    ##
    # Install one or more dependencies
    def install(*deps)
      options = Hash === deps.last ? deps.delete_at(deps.length - 1) : {}
      deps.each{|dep| self.dependencies[dep].install! options }
    end

    ##
    # Uninstall one or more dependencies
    def uninstall(*deps)
      options = Hash === deps.last ? deps.delete_at(deps.length - 1) : {}
      deps.each{|dep| self.dependencies[dep].uninstall! options }
    end

  end


  ##
  # Define internal Settler dependencies

  dependency 'yum' do
    install do |cmd|
      cmd.call "cd ~; mkdir -p setups; cd setups"
      cmd.call "wget -nv http://yum.baseurl.org/download/3.2/yum-3.2.25.tar.gz"
      cmd.call "tar -xvzf yum-3.2.25.tar.gz"
      cmd.call "cd yum-3.2.25; ./configure; make; make install"
      cmd.call "cd ~/setups; rm yum-3.2.25.tar.gz"
    end

    check_test "yum --version", "= \"3.2.25\""
  end

end
