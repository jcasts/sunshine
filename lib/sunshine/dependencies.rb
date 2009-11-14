require "settler"

class Sunshine::Dependencies < Settler

  yum 'nginx'

  yum 'ruby'

  gem 'unicorn', :version => "~>0.93"

  gem 'rainbows', :version => "0.4.0"

end

# Sunshine::Dependencies.install :nginx, :rainbows, :console => lambda{ |cmd| deploy_server.run(cmd) }

