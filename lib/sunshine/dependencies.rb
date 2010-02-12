require "settler"

##
# Defines Sunshine deploy server dependencies.

class Sunshine::Dependencies < Settler

  yum 'tpkg'

  yum 'svn', :pkg => 'subversion'

  yum 'git', :pkg => 'git-core'

  yum 'nginx'

  yum 'logrotate'

  yum 'ruby', :pkg => 'ruby-ypc'

  yum 'ruby-devel'

  yum 'irb', :pkg => 'ruby-irb'

  yum 'rubygems', :version => '1.3.5'

  yum 'logrotate'

  yum 'curl-devel'

  gem 'mogwai_logpush',
    :version => "~>0.0.2",
    :source  => "http://gems.atti.wc1.yellowpages.com" do
    requires 'curl-devel'
  end

  gem 'rake', :version => "~>0.8"

  gem 'passenger', :version => "~>2.2"

  gem 'bundler', :version => "~>0.7"

  gem 'geminstaller', :version => "~>0.5"

  gem 'unicorn', :version => "=>0.9"

  gem 'rainbows', :version => ">=0.6.0"

end
