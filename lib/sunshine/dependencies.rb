require "settler"

class Sunshine::Dependencies < Settler

  #yum 'nginx'

  #yum 'ruby'

  gem 'bundler'

  gem 'geminstaller'

  gem 'passenger', :version => "~>2.2.7"

  gem 'unicorn', :version => "~>0.93"

  gem 'rainbows', :version => "0.5.0"

end
