module Sunshine

  ##
  # The Apt dependency class supports basic apt-get features:
  #
  #   dependency_lib.instance_eval do
  #     apt "ruby", :version => '1.9'
  #   end
  #
  # See the Dependency class for more info.

  class Apt < Dependency

    self.sudo = true

    def initialize(name, options={}, &block)
      super(name, options) do
        pkg_name = build_pkg_name @pkg.dup, options

        install    "apt-get install -y #{pkg_name}"
        uninstall  "apt-get remove -y #{pkg_name}"

        @pkg = "#{@pkg}-#{options[:version]}" if options[:version]
        check_test "apt-cache search ^#{@pkg} | grep -c ^#{@pkg}", '-ge 1'

        instance_eval(&block) if block_given?
      end
    end


    ##
    # Checks if dependency type is valid for a given shell.

    def self.system_manager? shell=nil
      shell ||= Sunshine.shell
      shell.call("apt-get --version") && true rescue false
    end


    private

    def build_pkg_name pkg_name, options={}
      pkg_name << "=#{options[:version]}" if options[:version]

      pkg_name
    end


    def run_command(command, options={})
      if @dependency_lib
        if @dependency_lib.exist?('apt')
          @dependency_lib.install 'apt', options
        end
      end

      super
    end
  end
end
