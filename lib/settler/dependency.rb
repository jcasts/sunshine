class Settler

  class CmdError < Exception; end
  class InstallError < Exception; end
  class UninstallError < Exception; end

  class Dependency

    attr_reader :name

    def initialize(dependency_lib, name, &block)
      @dependency_lib = dependency_lib
      @name = name.to_s
      @install = nil
      @uninstall = nil
      @check = nil
      @parents = []
      @children = []
      @cmd = method(:run_local).to_proc
      instance_eval(&block) if block_given?
    end

    def install(cmd=nil, &block)
      @install = cmd || block
    end

    def uninstall(cmd=nil, &block)
      @uninstall = cmd || block
    end

    def check(cmd_str=nil, &block)
      @check = cmd_str || block
      @check = proc{|cmd| cmd.call(cmd_str).strip != "false" } if String === @check
    end

    def requires(*deps)
      @parents.concat(deps).uniq!
      deps.each do |dep|
        @dependency_lib.dependencies[dep].add_child(@name)
      end
    end

    def parent_dependencies
      @parents
    end

    def add_child(name)
      @children << name
    end

    def child_dependencies
      @children
    end

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
      raise(InstallError, "Failed installing #{@name}") unless installed?(options)
    end

    def install_parents!(options={})
      @parents.each do |dep|
        @dependency_lib.dependencies[dep].install!(options)
      end
    end

    def uninstall!(options={})
      raise(UninstallError, "The #{@name} has child dependencies. If you want to remove it anyway, use :force => true or :remove_children => (true || :recursive)") if !options[:remove_children] && !options[:force]
      uninstall_children!(options) if options[:remove_children]
      run_command(@uninstall, options)
      raise(UninstallError, "Failed removing #{@name}") if installed?(options)
    end

    def uninstall_children!(options={})
      options = options.dup
      @children.each do |dep|
        options.delete(:remove_children) unless options[:remove_children] == :recursive
        @dependency_lib.dependencies[dep].uninstall!(options)
      end
    end

    def installed?(options={})
      run_command(@check, options)
    rescue CmdError
      false
    end

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
      cmd = options[:console] || @cmd
      if Proc === command
        command.call(cmd)
      else
        cmd.call(command)
      end
    end

    def run_local(str)
      stdin, stdout, stderr = Open3.popen3(str)
      stderr = stderr.read
      raise(CmdError, "#{stderr}  when attempting to run '#{str}'") unless stderr.empty?
      stdout.read.strip
    end

  end

end
