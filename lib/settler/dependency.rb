class Settler

  class CmdError < Exception; end
  class InstallError < Exception; end
  class UninstallError < Exception; end

  class Dependency


    attr_reader :name, :pkg, :parents, :children

    def initialize(dependency_lib, name, options={}, &block)
      @dependency_lib = dependency_lib
      @name = name.to_s
      @pkg = options[:pkg] || @name
      @install = nil
      @uninstall = nil
      @check = nil
      @parents = []
      @children = []
      @cmd = method(:run_local).to_proc
      instance_eval(&block) if block_given?
    end

    ##
    # Define the install command for the dependency
    def install(cmd=nil, &block)
      @install = cmd || block
    end

    ##
    # Define the uninstall command for the dependency
    def uninstall(cmd=nil, &block)
      @uninstall = cmd || block
    end

    ##
    # Define the command that checks if the dependency is installed
    # The check command must echo true or false
    def check(cmd_str=nil, &block)
      @check = cmd_str || block
      @check = proc{|cmd| cmd.call(cmd_str) && true rescue false } if
        String === @check
    end

    ##
    # Define checking that the dependency is installed via unix's 'test'
    def check_test(cmd_str, condition_str)
      check "test \"$(#{cmd_str})\" #{condition_str}"
    end

    ##
    # Define which dependencies this dependency relies on
    def requires(*deps)
      @parents.concat(deps).uniq!
      deps.each do |dep|
        @dependency_lib.dependencies[dep].add_child(@name)
      end
    end

    ##
    # Get direct parent dependencies
    def parent_dependencies
      @parents
    end

    ##
    # Append a child dependency
    def add_child(name)
      @children << name
    end

    ##
    # Get direct child dependencies
    def child_dependencies
      @children
    end

    ##
    # Run the install command for the dependency
    # Allows option:
    # :skip_parents:: true - install regardless of missing parent dependencies
    def install!(options={})
      return if installed?(options)

      if options[:skip_parents]
        if missing_parent?
          raise(InstallError, "Could not install #{@name}. "+
            "Missing dependencies #{missing.join(", ")}")
        end
      else
        install_parents!(options)
      end

      run_command(@install, options)
      raise(InstallError, "Failed installing #{@name}") unless
        installed?(options)
    end

    ##
    # Call install on direct parent dependencies
    # Allows option:
    # :skip_parents:: true - install regardless of missing parent dependencies
    def install_parents!(options={})
      @parents.each do |dep|
        @dependency_lib.dependencies[dep].install!(options)
      end
    end

    ##
    # Run the uninstall command for the dependency
    # Allows options:
    # :force:: true - uninstalls regardless of child dependencies
    # :remove_children:: true - removes direct child dependencies
    # :remove_children:: :recursive - removes children recursively
    def uninstall!(options={})
      if !options[:remove_children] && !options[:force]
        raise UninstallError, "The #{@name} has child dependencies."
      end
      uninstall_children!(options) if options[:remove_children]
      run_command(@uninstall, options)
      raise(UninstallError, "Failed removing #{@name}") if installed?(options)
    end

    ##
    # Removes child dependencies
    # Allows options:
    # :force:: true - uninstalls regardless of child dependencies
    # :remove_children:: true - removes direct child dependencies
    # :remove_children:: :recursive - removes children recursively
    def uninstall_children!(options={})
      options = options.dup
      @children.each do |dep|
        options.delete(:remove_children) unless
          options[:remove_children] == :recursive
        @dependency_lib.dependencies[dep].uninstall!(options)
      end
    end

    ##
    # Run the check command to verify that the dependency is installed
    def installed?(options={})
      run_command(@check, options)
    rescue CmdError => e
      false
    end

    ##
    # Checks if any parents dependencies are missing
    def missing_parents?(options={})
      missing = []
      @parents.each do |dep|
        parent_dep = @dependency_lib.dependencies[dep]
        missing << dep unless parent_dep.installed?(options)
        return missing if options[:limit] && options[:limit] == missing.length
      end
      missing.empty? ? nil : missing
    end


    private

    def run_command(command, options={})
      cmd = options[:call] || @cmd
      if String === command
        cmd.call(command)
      else
        command.call(cmd)
      end
    end

    def run_local(str)
      result = nil
      Open4.popen4(str) do |pid, stdin, stdout, stderr|
        stderr = stderr.read
        raise(CmdError, "#{stderr}  when attempting to run '#{str}'") unless
          stderr.empty?
        result = stdout.read.strip
      end
      result
    end

    def self.inherited(subclass)
      class_name = subclass.to_s.split(":").last
      method_name = class_name.gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
       gsub(/([a-z\d])([A-Z])/,'\1_\2').downcase
      Settler.class_eval <<-STR, __FILE__, __LINE__ + 1
      def self.#{method_name}(name, options={}, &block)
        dependencies[name] = #{class_name}.new(self, name, options, &block)
      end
      STR
    end

    inherited self

  end

end
