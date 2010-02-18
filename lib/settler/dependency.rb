class Settler

  class CmdError < Exception; end
  class InstallError < Exception; end
  class UninstallError < Exception; end


  ##
  # Dependency objects let you define how to install, check, and remove
  # a described package, including parent dependency lookup and installation.
  #
  #   Dependency.new(Settler, "ruby") do
  #     install    "sudo yum install ruby"
  #     uninstall  "sudo yum remove ruby"
  #     check_test "yum list installed ruby | grep -c ruby", "-ge 1"
  #   end
  #
  # Dependencies are more commonly defined through a Settler class'
  # constructor methods:
  #
  #   class MyDeps < Settler
  #     dependency 'custom' do
  #       requires  'yum', 'ruby'
  #       install   'sudo yum install custom'
  #       uninstall 'sudo yum remove custom'
  #       check     'yum list installed custom'
  #     end
  #   end
  #
  # The Dependency class is simple to inherit and use as a built-in part of
  # Settler (see the Yum implementation for more info):
  #
  #   class Yum < Dependency
  #     def initialize(dep_lib, name, options={}, &block)
  #       super(dep_lib, name, options) do
  #         # Define install, check, and uninstall scripts specific to yum
  #       end
  #     end
  #     ...
  #   end
  #
  # Once a subclass is defined a constructor method is added automatically
  # to the Settler class:
  #
  #   class MyDeps < Settler
  #     yum "ruby", :version => '1.9'
  #   end

  class Dependency

    ##
    # Check if sudo should be used

    def self.sudo
      @sudo ||= nil
    end


    ##
    # Assign a sudo value. A value of nil means 'don't assign sudo',
    # true means sudo, string means sudo -u, false means, explicitely
    # don't use sudo. Yum and Gem dependency types default to sudo=true.

    def self.sudo= value
      @sudo = value
    end


    attr_reader :name, :pkg, :parents, :children

    def initialize dependency_lib, name, options={}, &block
      @dependency_lib = dependency_lib

      @name    = name.to_s
      @pkg     = options[:pkg] || @name
      @options = options.dup

      @install   = nil
      @uninstall = nil
      @check     = nil

      @parents  = []
      @children = []

      @cmd = method(:run_local).to_proc

      requires(*options[:require]) if options[:require]

      instance_eval(&block) if block_given?
    end


    ##
    # Append a child dependency

    def add_child name
      @children << name
    end


    ##
    # Get direct child dependencies

    def child_dependencies
      @children
    end


    ##
    # Define the command that checks if the dependency is installed.
    # The check command must have an appropriate exitcode:
    #
    #   dep.check "test -s 'yum list installed depname'"

    def check cmd_str=nil
      @check = cmd_str
    end


    ##
    # Define checking that the dependency is installed via unix's 'test':
    #
    #   dep.check_test "yum list installed depname | grep -c depname", "-ge 1"

    def check_test cmd_str, condition_str
      check "test \"$(#{cmd_str})\" #{condition_str}"
    end


    ##
    # Define the install command for the dependency:
    #
    #   dep.install "yum install depname"

    def install cmd
      @install = cmd
    end


    ##
    # Run the install command for the dependency
    # Allows options:
    # :call:: obj - an object that responds to call will be passed the bash cmd
    # :skip_parents:: true - install regardless of missing parent dependencies
    #
    #   runner = lambda{|str| system(str)}
    #   dep.install! :call => runner

    def install! options={}
      return if installed?(options)

      if options[:skip_parents]
        missing = missing_parents?
        if missing
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
    # Allows options:
    # :call:: obj - an object that responds to call will be passed the bash cmd
    #
    #   runner = lambda{|str| system(str)}
    #   dep.install_parents! :call => runner

    def install_parents! options={}
      @parents.each do |dep|
        @dependency_lib.dependencies[dep].install!(options)
      end
    end


    ##
    # Run the check command to verify that the dependency is installed
    # Allows options:
    # :call:: obj - an object that responds to call will be passed the bash cmd
    #
    #   runner = lambda{|str| system(str)}
    #   dep.installed? :call => runner

    def installed? options={}
      run_command @check, options
    rescue => e
      false
    end


    ##
    # Checks if any parents dependencies are missing
    # Allows options:
    # :call:: obj - an object that responds to call will be passed the bash cmd
    #
    #   runner = lambda{|str| system(str)}
    #   dep.missing_parents? :call => runner


    def missing_parents? options={}
      missing = []
      @parents.each do |dep|
        parent_dep = @dependency_lib.dependencies[dep]

        missing << dep unless parent_dep.installed?(options)

        return missing if options[:limit] && options[:limit] == missing.length
      end

      missing.empty? ? nil : missing
    end


    ##
    # Get direct parent dependencies

    def parent_dependencies
      @parents
    end


    ##
    # Define which dependencies this dependency relies on:
    #
    #  dep.requires 'rubygems', 'rdoc'

    def requires *deps
      @parents.concat(deps).uniq!
      deps.each do |dep|
        @dependency_lib.dependencies[dep].add_child(@name)
      end
    end


    ##
    # Define the uninstall command for the dependency:
    #
    #   dep.uninstall "yum remove depname"

    def uninstall cmd
      @uninstall = cmd
    end


    ##
    # Run the uninstall command for the dependency
    # Allows options:
    # :call:: obj - an object that responds to call will be passed the bash cmd
    # :force:: true - uninstalls regardless of child dependencies
    # :remove_children:: true - removes direct child dependencies
    # :remove_children:: :recursive - removes children recursively

    def uninstall! options={}
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
    # :call:: obj - an object that responds to call will be passed the bash cmd
    # :force:: true - uninstalls regardless of child dependencies
    # :remove_children:: true - removes direct child dependencies
    # :remove_children:: :recursive - removes children recursively

    def uninstall_children! options={}
      options = options.dup

      @children.each do |dep|
        options.delete(:remove_children) unless
          options[:remove_children] == :recursive

        @dependency_lib.dependencies[dep].uninstall!(options)
      end
    end


    ##
    # Alias for name

    def to_s
      @name
    end


    private

    def run_command(command, options={})
      cmd = options[:call] || @cmd

      unless self.class.sudo.nil?
        cmd.call command, :sudo => self.class.sudo
      else
        cmd.call command
      end
    end


    def run_local str, options={}
      result = nil

      str = "sudo #{str}" if options[:sudo] == true
      str = "sudo -u #{options[:sudo]} #{str}" if String === options[:sudo]

      Open4.popen4(str) do |pid, stdin, stdout, stderr|
        stderr = stderr.read

        raise(CmdError, "#{stderr}  when attempting to run '#{str}'") unless
          stderr.empty?

        result = stdout.read.strip
      end

      result
    end


    def self.inherited(subclass)
      class_name  = subclass.to_s.split(":").last
      method_name = class_name.gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
       gsub(/([a-z\d])([A-Z])/,'\1_\2').downcase

      Settler.class_eval <<-STR, __FILE__, __LINE__ + 1
      def self.#{method_name}(name, options={}, &block)
        dependencies[name] = #{class_name}.new(self, name, options, &block)
      end
      STR

      Settler.dependency_types << subclass
    end

    inherited self

  end
end
