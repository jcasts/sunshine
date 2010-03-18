# Dependencies that need fixing for ATTi VMs

Sunshine.dependencies.instance_eval do

  tpkg 'git'

  yum 'ruby-devel', :arch => "$(uname -p)"

  yum 'ruby', :pkg => 'ruby-ypc'

  yum 'libaio'

  gem 'ruby-oci8'

  gem 'activerecord-oracle_enhanced-adapter' do
    requires 'libaio', 'ruby-oci8'
  end

  gem 'mogwai_logpush',
    :version => ">=0.0.2",
    :source  => "http://gems.atti.wc1.yellowpages.com" do
    requires 'curl-devel'
  end
end


