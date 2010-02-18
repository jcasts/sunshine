
# Dependencies that need fixing for ATTi VMs

class Sunshine::Dependencies < Settler

  tpkg 'git'

  yum 'ruby-devel', :arch => 'x86_64'

  yum 'ruby', :pkg => 'ruby-ypc'
end
