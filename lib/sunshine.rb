require 'yaml'

module Sunshine

  require 'sunshine/commands'
  require 'sunshine/deploy_server'
  require 'sunshine/app'
  #require "sunshine/servers/server"
  #require "sunshine/servers/nginx_server"
  #require "sunshine/servers/unicorn_server"
  #require "sunshine/servers/rainbows_server"

  class << self

    def deploy_env
      :qa
    end

  end

end
