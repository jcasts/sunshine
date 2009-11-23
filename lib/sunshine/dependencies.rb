require "settler"

class Sunshine::Dependencies < Settler

  #yum 'nginx'

  #yum 'ruby'

  gem 'geminstaller'

  gem 'unicorn', :version => "~>0.93"

  gem 'rainbows', :version => "0.5.0"

end
