class Settler

  class CmdError < Exception; end
  class InstallError < Exception; end
  class UninstallError < Exception; end

  class Dependency


    attr_reader :name

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
      @check = proc{|cmd| cmd.call(cmd_str).strip == "true" } if
        String === @check
    end

    ##
    # Define checking that the dependency is installed via unix's 'test'
    def check_test(cmd_str, condition_str)
      check "test \"$(#{cmd_str})\" #{condition_str} && echo true || echo false"
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
    # Allows option: :skip_parents => true
    def install!(options={})
      return if installed?(options)

      if options[:skip_parents]
        missing = missing_parent?
        if missing
          raise(InstallError, "Could not install #{@name}. \
Missing dependencies #{missing.join(", ")}")
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
    # Allows option: :skip_parents => true
    def install_parents!(options={})
      @parents.each do |dep|
        @dependency_lib.dependencies[dep].install!(options)
      end
    end

    ##
    # Run the uninstall command for the dependency
    # Allows options:
    #   :force => true - uninstalls regardless of child dependencies
    #   :remove_children => true - removes direct child dependencies
    #   :remove_children => :recursive - removes children recursively
    def uninstall!(options={})
      if !options[:remove_children] && !options[:force]
        raise UninstallError,
          "The #{@name} has child dependencies. "+
          "If you want to remove it anyway, use :force => true or "+
          ":remove_children => (true || :recursive)"
      end
      uninstall_children!(options) if options[:remove_children]
      run_command(@uninstall, options)
      raise(UninstallError, "Failed removing #{@name}") if installed?(options)
    end

    ##
    # Removes child dependencies
    # Allows options:
    #   :force => true - uninstalls regardless of child dependencies
    #   :remove_children => true - removes direct child dependencies
    #   :remove_children => :recursive - removes children recursively
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
      stdin, stdout, stderr = Open3.popen3(str)
      stderr = stderr.read
      raise(CmdError, "#{stderr}  when attempting to run '#{str}'") unless
        stderr.empty?
      stdout.read.strip
    end

    def self.register_with_settler(method_name=nil)
      class_name = self.to_s.split(":").last
      method_name ||= class_name.downcase
      Settler.class_eval <<-STR
      def self.#{method_name}(name, options={}, &block)
        dependencies[name] = #{class_name}.new(self, name, options, &block)
      end
      STR
    end

    register_with_settler

  end

end
