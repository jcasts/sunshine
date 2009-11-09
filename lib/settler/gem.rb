class Settler

  class Gem < Dependency

    def initialize(dependency_lib, name, options={}, &block)
      @dependency_lib = dependency_lib
      @name = name.to_s
      @install = "gem install #{@name}"
      @uninstall = "gem uninstall #{@name}"
      @check = "gem list #{@name} -i"
      if options[:version]
        @install = "#{@install} --version '#{options[:version]}'"
        @uninstall = "#{@uninstall} --version '#{options[:version]}'"
        @check = "#{@check} --version '#{options[:version]}'"
      end
      @parents = []
      @children = []
      @cmd = method(:run_local).to_proc
      instance_eval(&block) if block_given?
    end

  end

end
