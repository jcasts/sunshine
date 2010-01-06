require "settler"

##
# Defines Sunshine deploy server dependencies.
class Sunshine::Dependencies < Settler

  yum 'subversion'

  yum 'nginx'

  yum 'logrotate'

  yum 'ruby', :pkg => 'ruby-ypc'

  yum 'rubygems' do
    requires 'ruby'
    install  'yum install -y rubygems && gem update --system --no-ri --no-rdoc'
    check do |cmd|
      cmd.call("gem -v || echo 0").strip >= '1.3.5'
    end
  end

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

  gem 'unicorn', :version => "~>0.9"

  gem 'rainbows', :version => "0.6.0"

end
