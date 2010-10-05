module Sunshine

  ##
  # Dependency objects let you define how to install, check, and remove
  # a described package, including parent dependency lookup and installation.
  #
  #   Dependency.new "ruby", :tree => dependency_lib do
  #     install    "sudo yum install ruby"
  #     uninstall  "sudo yum remove ruby"
  #     check_test "yum list installed ruby | grep -c ruby", "-ge 1"
  #   end
  #
  # Dependencies are more commonly defined through a Settler class'
  # constructor methods:
  #
  #   dependency_lib.instance_eval do
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
  #     def initialize(name, options={}, &block)
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
  #   dependency_lib.instance_eval do
  #     yum "ruby", :version => '1.9'
  #   end

  class Dependency

    class InstallError < Exception; end
    class UninstallError < Exception; end


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


    ##
    # Checks if dependency type is valid for a given shell.
    # Defaults to false. Override in subclass.

    def self.system_manager? shell=nil
      false
    end


    attr_reader :name, :pkg, :parents, :children

    def initialize name, options={}, &block
      @dependency_lib = options[:tree]

      @name    = name.to_s
      @pkg     = options[:pkg] || @name
      @options = options.dup

      @install   = nil
      @uninstall = nil
      @check     = nil

      @parents  = []
      @children = []

      @shell = Sunshine.shell

      requires(*options[:requires]) if options[:requires]

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

    def check cmd_str=nil, &block
      @check = cmd_str || block
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

    def install cmd=nil, &block
      @install = cmd || block
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
      return unless @dependency_lib

      @parents.each do |dep|
        @dependency_lib.get(dep, options).install!(options)
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
      return unless @dependency_lib

      missing = []
      @parents.each do |dep|
        parent_dep = @dependency_lib.get dep, options

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
      return unless @dependency_lib

      @parents.concat(deps).uniq!
      deps.each do |dep|
        @dependency_lib.dependencies[dep].each{|d| d.add_child(@name) }
      end
    end


    ##
    # Define the uninstall command for the dependency:
    #
    #   dep.uninstall "yum remove depname"

    def uninstall cmd=nil, &block
      @uninstall = cmd || block
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
      return unless @dependency_lib

      options = options.dup

      @children.each do |dep|
        options.delete(:remove_children) unless
          options[:remove_children] == :recursive

        @dependency_lib.get(dep, options).uninstall!(options)
      end
    end


    ##
    # Alias for name

    def to_s
      @name
    end


    private

    def run_command command, options={}
      shell = options[:call] || @shell

      if Proc === command
        command.call shell, self.class.sudo

      else
        shell.call command, :sudo => self.class.sudo
      end
    end


    ##
    # Returns an underscored short version of the class name:
    #   Sunshine::Yum.short_name
    #   #=> "yum"

    def self.short_name
      @short_name ||= underscore self.name.to_s.split(":").last
    end


    def self.underscore str
      str.gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
        gsub(/([a-z\d])([A-Z])/,'\1_\2').downcase
    end


    ##
    # Auto register the new Dependency class with DependencyLib and ServerApp
    # when inherited.

    def self.inherited subclass
      DependencyLib.register_type subclass
      ServerApp.register_dependency_type subclass
    end

    inherited self

  end
end
