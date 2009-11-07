require "settler"

class Sunshine::Dependencies < Settler

  dependency :nginx do
    install   "yum install nginx"
    uninstall "yum remove nginx"
    check do |cmd|
      begin
        cmd.call("yum list nginx") && true
      rescue Sunshine::CmdError
        false
      end
    end
  end

  dependency :ruby do
    install   "yum install ruby"
    uninstall "yum remove ruby"
    check do |cmd|
      begin
        cmd.call("ruby -v") && true
      rescue(Sunshine::CmdError)
        false
      end
    end
  end

  dependency :rainbows do
    requires  :ruby
    install   "gem install rainbows"
    uninstall "gem uninstall rainbows"
    check     "gem list rainbows -i"
  end

end

# Sunshine::Dependencies.install :nginx, :rainbows, :console => lambda{ |cmd| deploy_server.run(cmd) }

