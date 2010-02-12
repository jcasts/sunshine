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
  require 'settler/yum'
  require 'settler/apt_get'
  require 'settler/gem'
  require 'settler/tpkg'


  ##
  # Returns a single dependency by name:
  #   Settler['name'] #=> dependency object

  def self.[](key)
    (@dependencies ||= {})[key]
  end


  ##
  # Hash of 'name' => object dependencies

  def self.dependencies
    @dependencies ||= {}
  end


  ##
  # Checks for the existance of a dependency by name

  def self.exist?(key)
    self.dependencies.has_key?(key)
  end


  ##
  # Install one or more dependencies:
  #
  #   Dependencies.install 'dep1', 'dep2', options_hash
  #
  # See Dependency#install! for supported options.

  def self.install(*deps)
    options = Hash === deps.last ? deps.delete_at(deps.length - 1) : {}
    deps.each{|dep| self.dependencies[dep].install! options }
  end


  ##
  # Uninstall one or more dependencies:
  #
  #   Dependencies.uninstall 'dep1', 'dep2', options_hash
  #
  # See Dependency#uninstall! for supported options.


  def self.uninstall(*deps)
    options = Hash === deps.last ? deps.delete_at(deps.length - 1) : {}
    deps.each{|dep| self.dependencies[dep].uninstall! options }
  end


  ##
  # Define if sudo should be used

  def self.sudo= value
    dependency_types.each do |dep_class|
      dep_class.sudo = value
    end
  end
end
