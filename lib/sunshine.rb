require 'yaml'
require 'open3'
require 'net/ssh'
require 'net/scp'
require 'erb'


module Sunshine

  require 'sunshine/repo'
  require 'sunshine/repos/svn_repo'

  require 'sunshine/deploy_server'
  require 'sunshine/app'
  #require "sunshine/servers/server"
  #require "sunshine/servers/nginx_server"
  #require "sunshine/servers/unicorn_server"
  #require "sunshine/servers/rainbows_server"


  class CmdError < Exception; end

  class << self

    include Open3

    def deploy_env
      :qa
    end

    def run_local(str)
      stdin, stdout, stderr = popen3(str)
      stderr = stderr.read
      raise(CmdError, "#{stderr}  when attempting to run '#{str}'") unless stderr.empty?
      stdout.read
    end

  end

end
