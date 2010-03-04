# Dependencies that need fixing for ATTi VMs

class Sunshine::Dependencies < Settler

  tpkg 'git'

  yum 'ruby-devel', :arch => "$(uname -p)"

  yum 'ruby', :pkg => 'ruby-ypc'
end


