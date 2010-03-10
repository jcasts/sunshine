require 'open4'

##
# Settler is a simple tool for building and handling depenedencies.
# A dependency tree can be defined by inheriting the Settler class, and
# dependencies can be defined through settler dependency instantiation methods:
#
#   class MyDependencies < Settler
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
#   MyDependencies.install 'rdoc', 'ri'
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

class Settler

  ##
  # Array of all dependency classes. Appended to automatically when
  # Settler::Dependency is inherited.

  def self.dependency_types
    @dependency_types ||= []
  end


  require 'settler/dependency'
  require 'settler/apt'
  require 'settler/yum'
  require 'settler/gem'
  require 'settler/tpkg'


  ##
  # Returns a dependency hash by type:
  #   Settler['name'] #=> {:yum => <Yum...>, :apt => <Apt...>, ...}

  def self.[](key)
    self.dependencies[key]
  end


  ##
  # Add a dependency to the dependencies hash.

  def self.add dep
    (self.dependencies[dep.name] ||= []).unshift dep
  end


  ##
  # Hash of 'name' => object dependencies

  def self.dependencies
    @dependencies ||= Hash.new
  end


  ##
  # Checks for the existance of a dependency by name

  def self.exist?(key)
    self.dependencies.has_key? key
  end


  ##
  # Get a dependency object by name. Supports passing :type => :pkg_manager
  # if dependencies with the same name but different package managers exist:
  #   Dependencies.get 'daemon', :type => Settler::Gem
  #   #=> <Gem @name="daemon"...>
  #
  # For an 'nginx' dependency defined for both apt and yum, where the yum
  # dependency object was added to the tree last:
  #   Dependencies.get 'nginx'
  #   #=> <Yum @name="nginx"...>
  #
  #   Dependencies.get 'nginx', :type => Settler::Apt
  #   #=> <Apt @name="nginx"...>
  #
  # Use the :prefer option if a certain dependency type is prefered but
  # will fall back to whatever first dependency is available:
  #   Dependencies.yum 'my_dep'
  #   Dependencies.get 'my_dep', :prefer => Settler::Apt
  #   #=> <Yum @name="my_dep"...>

  def self.get name, options={}
    return unless self.dependencies.has_key? name

    deps     = self.dependencies[name]
    dep_type = options[:type] || options[:prefer]

    return deps.first unless dep_type

    deps.each do |dep|
      return dep if dep_type === dep
    end

    return deps.first unless options[:type]
  end


  ##
  # Install one or more dependencies:
  #
  #   Dependencies.install 'dep1', 'dep2', options_hash
  #
  # See Settler::get and Dependency#install! for supported options.

  def self.install(*deps)
    send_each(:install!, *deps)
  end


  ##
  # Uninstall one or more dependencies:
  #
  #   Dependencies.uninstall 'dep1', 'dep2', options_hash
  #
  # See Settler::get and Dependency#uninstall! for supported options.

  def self.uninstall(*deps)
    send_each(:uninstall!, *deps)
  end


  ##
  # Get and call method on each dependency passed

  def self.send_each(method, *deps)
    options = Hash === deps.last ? deps.delete_at(deps.length - 1).dup : {}

    #if options[:call].respond_to? :pkg_manager
    #  options[:prefer] ||= options[:call].pkg_manager
    #end

    deps.each do |dep|
      dep = self.get(dep, options) if String === dep
      dep.send method, options
    end
  end


  ##
  # Define if sudo should be used

  def self.sudo= value
    dependency_types.each do |dep_class|
      dep_class.sudo = value
    end
  end
end
