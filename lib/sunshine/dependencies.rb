##
# Defines Sunshine deploy server dependencies.

#class Sunshine::Dependencies < Settler
Sunshine.dependencies.instance_eval do

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

  apt 'irb'
  yum 'irb', :pkg => 'ruby-irb'

  apt 'rubygems', :version => '1.3.5' do
    requires 'ruby', 'ruby-devel'
  end
  yum 'rubygems', :version => '1.3.5' do
    requires 'ruby', 'ruby-devel'
  end

  apt 'logrotate'
  yum 'logrotate'

  apt 'curl-devel', :pkg => 'libcurl-dev'
  yum 'curl-devel'

  apt 'libxml2-devel', :pkg => 'libxml2-dev'
  yum 'libxml2-devel'

  apt 'libxslt-devel', :pkg => 'libxslt-dev'
  yum 'libxslt-devel'

  apt 'sqlite', :pkg => 'sqlite3'
  yum 'sqlite'

  apt 'sqlite-devel', :pkg => 'libsqlite3-dev'
  yum 'sqlite-devel'


  # Define gems used by Sunshine

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
