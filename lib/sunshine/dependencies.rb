require "settler"

##
# Defines Sunshine deploy server dependencies.

class Sunshine::Dependencies < Settler

  yum 'tpkg'

  yum 'svn', :pkg => 'subversion'

  yum 'git', :pkg => 'git-core'

  yum 'nginx'

  yum 'logrotate'

  yum 'ruby'

  yum 'ruby-devel'

  yum 'irb', :pkg => 'ruby-irb'

  yum 'rubygems', :version => '1.3.5' do
    requires 'ruby', 'ruby-devel'
  end

  yum 'logrotate'

  yum 'curl-devel'

  yum 'libxml2-devel'

  yum 'libxslt-devel'

  yum 'sqlite'

  yum 'sqlite-devel'

  yum 'libaio'

  gem 'ruby-oci8'

  gem 'activerecord-oracle_enhanced-adapter' do
    requires 'libaio', 'ruby-oci8'
  end

  gem 'isolate'

  gem 'mogwai_logpush',
    :version => ">=0.0.2",
    :source  => "http://gems.atti.wc1.yellowpages.com" do
    requires 'curl-devel'
  end

  gem 'rake', :version => ">=0.8"

  gem 'passenger', :version => "~>2.2"

  gem 'bundler', :version => "~>0.7"

  gem 'geminstaller', :version => "~>0.5"

  gem 'unicorn', :version => ">=0.9"

  gem 'rainbows', :version => ">=0.90.2"

  gem 'ar_mailer', :version => ">=1.5.0"

  gem 'haml'

end
