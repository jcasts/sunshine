require 'rubygems'
require 'rainbow'

require 'settler'
require 'yaml'
require 'open3'
require 'net/ssh'
require 'net/scp'
require 'erb'
require 'logger'
require 'optparse'


module Sunshine

  VERSION = '0.0.1'

  class CmdError < Exception; end

  class SSHCmdError < CmdError
    attr_reader :deploy_server
    def initialize(message=nil, deploy_server=nil)
      @deploy_server = deploy_server
      super(message)
    end
  end

  class CriticalDeployError < Exception; end
  class FatalDeployError < Exception; end
  class DependencyError < FatalDeployError; end

  require 'sunshine/output'

  require 'sunshine/dependencies'

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



  def self.logger
    @logger ||= Sunshine::Output.new :level => @options['level']
  end

  def self.deploy_env
    @options['deploy_env']
  end

  def self.run_local(str)
    stdin, stdout, stderr = Open3.popen3(str)
    stderr = stderr.read
    raise(CmdError, "#{stderr}  when attempting to run '#{str}'") unless stderr.empty?
    stdout.read.strip
  end

  def self.parse_args argv
    options = {}

    opts = OptionParser.new do |opt|
      opt.program_name = File.basename $0
      opt.version = Sunshine::VERSION
      opt.release = nil
      opt.banner = <<-EOF

Usage: #{opt.program_name} deploy_file [options]

Sunshine is a gem that provides a light, consistant api for rack applications deployment. 
      EOF

      opt.separator nil

      opt.on('-l', '--level [LEVEL]',
             'Set trace level. Defaults to info.') do |value|
        options[:level] = value.downcase.to_sym
      end

      opt.on('-e', '--env [DEPLOY_ENV]',
             'Sets the deploy environment. Defaults to development.') do |value|
        options[:deploy_env] = value
      end

      opt.separator nil
      opt.separator "Common options:"

      opt.on_tail("-h", "--help", "Show this message") do
        puts opt
        exit
      end

      opt.on_tail("-v", "--version", "Sunshine version") do
        puts VERSION
        exit
      end

    end

    opts.parse! argv

    options
  end

  def self.run(argv=ARGV)
    self.setup( parse_args(argv) )

    deploy_file = argv.first
    unless File.file?(deploy_file.to_s)
      puts "Error: Can't load file '#{deploy_file}'"
      exit
    end

    require deploy_file
  end

  def self.setup(options=nil)
    @options ||= {
      :level => :info,
      :deploy_env => :development,
    }
    @options.merge!(options)
  end

end

