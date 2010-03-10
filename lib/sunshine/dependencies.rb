require "settler"

##
# Defines Sunshine deploy server dependencies.

class Sunshine::Dependencies < Settler

  yum 'tpkg'

  apt 'svn', :pkg => 'subversion'
  yum 'svn', :pkg => 'subversion'

  apt 'git', :pkg => 'git-core'
  yum 'git', :pkg => 'git-core'

  apt 'nginx'
  yum 'nginx'

  apt 'logrotate'
  yum 'logrotate'

  apt 'ruby', :pkg => 'ruby-full'
  yum 'ruby'

  apt 'ruby-devel', :pkg => 'ruby-dev'
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

  gem 'bundler', :version => ">=0.9"

  gem 'isolate', :version => ">=1.3.0"

  gem 'rake', :version => ">=0.8"

  gem 'passenger', :version => ">=2.2"

  gem 'geminstaller', :version => ">=0.5"

  gem 'unicorn', :version => ">=0.9"

  gem 'rainbows', :version => ">=0.90.2"

  gem 'ar_mailer', :version => ">=1.5.0"

  gem 'haml'

  gem 'daemons'

end
