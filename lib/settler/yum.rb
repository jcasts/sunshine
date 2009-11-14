class Settler

  class Yum < Dependency

    register_with_settler

    def initialize(dependency_lib, name, options={}, &block)
      super(dependency_lib, name, options) do
        pkg_name = @name.dup
        pkg_name << "-#{options[:version]}" if options[:version]
        pkg_name << "-#{options[:rel]}" if options[:version] && options[:rel]
        pkg_name << ".#{options[:arch]}" if options[:arch]
        pkg_name = "#{options[:epoch]}:#{pkg_name}" if options[:version] && options[:rel] && options[:arch] && options[:epoch]

        install "yum install #{pkg_name}"
        uninstall "yum remove #{pkg_name}"
        check_test("yum list #{pkg_name} | grep #{pkg_name} | wc -l", "-ge \"1\"")
        requires *(options[:require].to_a) if options[:require]
        instance_eval(&block) if block_given?
      end
    end

    private

    def run_command(command, options={})
      Settler.install 'yum', options
      super
    end

  end

end
