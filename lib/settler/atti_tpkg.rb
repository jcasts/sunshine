class Settler

  class AttiTpkg < Dependency

    register_with_settler "atti_tpkg"

    def initialize(dependency_lib, name, options={}, &block)
      super(dependency_lib, name, options) do
        pkg_name = @name.dup
        pkg_name << "-#{options[:version]}" if options[:version]
        pkg_name << (options[:arch] ? "-#{options[:arch]}" : "-$(uname -p)")

        install "tpkg -n -i http://tpkg/tpkg/#{pkg_name}.tpkg"
        uninstall "tpkg -n -r #{pkg_name}"
        check_test("tpkg -q #{@name} | grep #{@name} | wc -l", "-ge \"1\"")
        requires *(options[:require].to_a) if options[:require]
        instance_eval(&block) if block_given?
      end
    end

  end

end
