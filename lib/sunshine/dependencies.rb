require "settler"

##
# Defines Sunshine deploy server dependencies.
# TODO: Reinable yum or use a different bundle manager.
#       Yum is difficult to install from scratch - maybe use apt.
class Sunshine::Dependencies < Settler

  #yum 'nginx'

  #yum 'ruby'

  #yum 'logrotate'

  gem 'rake', :version => "~>0.8"

  gem 'chronic', :version => "~>0.2"

  gem 'javan-whenever', :version => "~>0.3" do
    requires 'chronic'
  end

  gem 'mogwai_logpush', :version => "~>0.0.2"

  gem 'passenger', :version => "~>2.2"

  gem 'bundler', :version => "~>0.7"

  gem 'geminstaller', :version => "~>0.5"

  gem 'unicorn', :version => "~>0.9"

  gem 'rainbows', :version => "0.5.0"

end
