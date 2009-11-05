require 'rubygems'
require 'yaml'
require 'open3'
require 'net/ssh'
require 'net/scp'
require 'erb'
require 'logger'


module Sunshine

  class CmdError < Exception; end

  require 'sunshine/repo'
  require 'sunshine/repos/svn_repo'

  require 'sunshine/healthcheck'

  require 'sunshine/deploy_server_dispatcher'
  require 'sunshine/deploy_server'
  require 'sunshine/app'

  require "sunshine/server"
  require "sunshine/servers/nginx"
  require "sunshine/servers/unicorn"
  require "sunshine/servers/rainbows"


  class << self

    include Open3

    def logger
      return @logger if @logger
      @logger = Logger.new(STDOUT)
      @logger.level = Logger::INFO
      @logger
    end

    def info(from, message, options={})
      new_lines = "\n" * (options[:nl] || 1)
      indent = " " * (options[:indent].to_i * 2)
      logger << "#{new_lines}#{indent}[#{from}] #{message}\n"
    end

    def deploy_env
      :qa
    end

    def run_local(str)
      stdin, stdout, stderr = popen3(str)
      stderr = stderr.read
      raise(CmdError, "#{stderr}  when attempting to run '#{str}'") unless stderr.empty?
      stdout.read.strip
    end

  end

end
