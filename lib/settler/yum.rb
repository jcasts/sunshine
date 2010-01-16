class Settler

  ##
  # The Yum dependency class supports most of yum's installation features:
  #
  #   class MyDeps < Settler
  #     yum "ruby", :version => '1.9',
  #                 :rel     => 'release-num',
  #                 :arch    => 'i386',
  #                 :epoch   => 'some-epoch'
  #   end
  #
  # See the Dependency class for more info.

  class Yum < Dependency

    def initialize(dependency_lib, name, options={}, &block)
      super(dependency_lib, name, options) do
        pkg_name = @pkg.dup
        pkg_name << "-#{options[:version]}" if options[:version]
        pkg_name << "-#{options[:rel]}" if options[:version] && options[:rel]
        pkg_name << ".#{options[:arch]}" if options[:arch]
        pkg_name = "#{options[:epoch]}:#{pkg_name}" if
          options[:version] && options[:rel] &&
          options[:arch] && options[:epoch]

        install    "sudo yum install -y #{pkg_name}"
        uninstall  "sudo yum remove -y #{pkg_name}"
        check_test "yum list installed #{pkg_name} | grep -c #{@pkg}", '-ge 1'

        instance_eval(&block) if block_given?
      end
    end


    private

    def run_command(command, options={})
      if @dependency_lib.exist?('yum')
        @dependency_lib.install 'yum', options
      end
      super
    end
  end
end
