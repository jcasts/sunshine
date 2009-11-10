class Settler

  class Yum < Dependency

    register_with_settler

    def initialize(dependency_lib, name, options={}, &block)
      @dependency_lib = dependency_lib
      @name = name.to_s

      pkg_name = @name.dup
      pkg_name << "-#{options[:version]}" if options[:version]
      pkg_name << "-#{options[:rel]}" if options[:version] && options[:rel]
      pkg_name << ".#{options[:arch]}" if options[:arch]
      pkg_name = "#{options[:epoch]}:#{pkg_name}" if options[:version] && options[:rel] && options[:arch] && options[:epoch]

      @install = "yum install #{pkg_name}"
      @uninstall = "yum remove #{pkg_name}"
      check_test("yum list #{pkg_name} | grep #{pkg_name} | wc -l", "-ge \"1\"")
      @parents = []
      @children = []
      @cmd = method(:run_local).to_proc
      instance_eval(&block) if block_given?
    end

  end

end
