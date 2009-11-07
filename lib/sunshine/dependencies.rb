require "settler"

class Sunshine::Dependencies < Settler

  dependency :nginx do
    requires :yum
    install   "yum install nginx"
    uninstall "yum remove nginx"
    check     { cmd("yum list nginx") rescue(Sunshine::CmdError) false }
  end

  dependency :rainbows do
    requires :rubygems
    install   "gem install rainbows"
    uninstall "gem uninstall rainbows"
    check     { cmd("gem list rainbows -i") == "true\n" }
  end

end

# Sunshine::Dependencies.install :nginx, :rainbows, :console => lambda{ |cmd| deploy_server.run(cmd) }

