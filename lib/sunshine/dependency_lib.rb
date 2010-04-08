module Sunshine

  ##
  # DependencyLib is a simple class for building and handling depenedencies.
  # A dependency tree can be defined by inheriting the DependencyLib class, and
  # dependencies can be defined through dependency instantiation methods:
  #
  #   dependency_lib.instance_eval do
  #
  #     yum 'ruby', :pkg => 'ruby-devel'
  #
  #     yum 'rubygems', :requires => 'ruby'
  #
  #     gem 'rdoc', :requires => 'rubygems'
  #
  #     gem 'ri', :requires => 'rubygems'
  #
  #   end
  #
  # Calling the install for rdoc will then check and install all of its parent
  # dependencies as well:
  #
  #   dependency_lib.install 'rdoc', 'ri'
  #
  # Dependencies may also be generic and/or have custom bash scripts
  # for installs, uninstalls, and presence checks:
  #
  #   dependency 'custom' do
  #     requires  'yum', 'ruby'
  #     install   'sudo yum install custom'
  #     uninstall 'sudo yum remove custom'
  #     check     'yum list installed custom'
  #   end
  #
  # See the Dependency class for more information.

  class DependencyLib

    class MissingDependency < Exception; end

    ##
    # Array of all dependency classes. Appended to automatically when
    # DependencyLib::Dependency is inherited.

    def self.dependency_types
      @dependency_types ||= []
    end


    ##
    # Registers a new dependency class, creates its constructor method
    # (DependencyLib#[dep_class.short_name]).

    def self.register_type dep_class
      class_eval <<-STR, __FILE__, __LINE__ + 1

        def #{dep_class.short_name}(name, options={}, &block)
          dep = #{dep_class}.new(name, options.merge(:tree => self), &block)
          self.add dep
          dep
        end
      STR

      dependency_types << dep_class
    end


    ##
    # Define if sudo should be used

    def self.sudo= value
      dependency_types.each do |dep_class|
        dep_class.sudo = value
      end
    end


    attr_reader :dependencies

    def initialize
      @dependencies = Hash.new
    end


    ##
    # Returns a dependency hash by type:
    #   DependencyLib['name'] #=> {:yum => <Yum...>, :apt => <Apt...>, ...}

    def [](key)
      @dependencies[key]
    end


    ##
    # Add a dependency to the dependencies hash.

    def add dep
      (@dependencies[dep.name] ||= []).unshift dep
    end


    ##
    # Checks for the existance of a dependency by name

    def exist? key
      @dependencies.has_key? key
    end


    ##
    # Get a dependency object by name. Supports passing :type => :pkg_manager
    # if dependencies with the same name but different package managers exist:
    #   dependencies.get 'daemon', :type => Gem
    #   #=> <Gem @name="daemon"...>
    #
    # For an 'nginx' dependency defined for both apt and yum, where the yum
    # dependency object was added to the tree last. Returns nil if
    # no matching dependency type is found:
    #   dependencies.get 'nginx'
    #   #=> <Yum @name="nginx"...>
    #
    #   dependencies.get 'nginx', :type => Apt
    #   #=> <Apt @name="nginx"...>
    #
    # Use the :prefer option if a certain dependency type is prefered but
    # will fall back to whatever first dependency is available:
    #   dependencies.yum 'my_dep'
    #   dependencies.get 'my_dep', :prefer => Apt
    #   #=> <Yum @name="my_dep"...>
    #
    # Both the :type and the :prefer options support passing arrays to search
    # from best to least acceptable candidate:
    #   dependencies.yum 'my_dep'
    #   dependencies.apt 'my_dep'
    #   dependencies.get 'my_dep', :type => [Tpkg, Yum]
    #   #=> <Yum @name="my_dep"...>

    def get name, options={}
      return unless exist? name

      deps      = @dependencies[name]
      dep_types = [*(options[:type] || options[:prefer])].compact

      return deps.first if dep_types.empty?

      dep_types.each do |dep_type|
        deps.each do |dep|
          return dep if dep_type === dep
        end
      end

      return deps.first unless options[:type]
    end


    ##
    # Install one or more dependencies:
    #
    #   dependencies.install 'dep1', 'dep2', options_hash
    #
    # See DependencyLib#get and Dependency#install! for supported options.
    #
    # Note: If a Dependency object is passed and the :type option is set,
    # DependencyLib will attempt to find and install a dependency of class :type
    # with the same name as the passed Dependency object:
    #   my_dep = dependencies.yum "my_dep_yum_only"
    #   dependencies.install my_dep, :type => Apt
    #   #=> "No dependency 'my_dep' [Sunshine::Apt]"

    def install(*deps)
      send_each(:install!, *deps)
    end


    ##
    # Uninstall one or more dependencies:
    #
    #   dependencies.uninstall 'dep1', 'dep2', options_hash
    #
    # See DependencyLib#get and Dependency#uninstall! for supported options.

    def uninstall(*deps)
      send_each(:uninstall!, *deps)
    end


    ##
    # Get and call method on each dependency passed

    def send_each(method, *deps)
      options = Hash === deps.last ? deps.delete_at(-1).dup : {}

      #if options[:call].respond_to? :pkg_manager
      #  options[:prefer] ||= options[:call].pkg_manager
      #end

      deps.each do |dep_name|
        dep = if Dependency === dep_name
                if options[:type] && !(options[:type] === dep_name)
                  get(dep_name.name, options)
                else
                  dep_name
                end
              else
                get(dep_name, options)
              end

        raise MissingDependency,
          "No dependency '#{dep_name}' [#{options[:type] || "any"}]" if !dep

        # Remove :type so dependencies of other types than dep can be installed
        options.delete(:type)

        dep.send method, options
      end
    end
  end
end
