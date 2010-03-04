# Dependencies that need fixing for ATTi VMs

class Sunshine::Dependencies < Settler

  tpkg 'git'

  yum 'ruby-devel', :arch => "$(uname -p)"

  yum 'ruby', :pkg => 'ruby-ypc'

  gem 'mogwai_logpush',
    :version => ">=0.0.2",
    :source  => "http://gems.atti.wc1.yellowpages.com" do
    requires 'curl-devel'
  end
end


