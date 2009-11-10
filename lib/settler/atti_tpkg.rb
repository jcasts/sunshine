class Settler

  class AttiTpkg < Dependency

    register_with_settler "atti_tpkg"

    def initialize(dependency_lib, name, options={}, &block)
      @dependency_lib = dependency_lib
      @name = name.to_s

      pkg_name = @name.dup
      pkg_name << "-#{options[:version]}" if options[:version]
      pkg_name << (options[:arch] ? "-#{options[:arch]}" : "-$(uname -p)")

      @install = "tpkg -n -i http://tpkg/tpkg/#{pkg_name}.tpkg"
      @uninstall = "tpkg -n -r #{pkg_name}"
      check_test("\"$(tpkg -q #{@name} | grep #{@name} | wc -l)\" -ge \"1\""
      @parents = []
      @children = []
      @cmd = method(:run_local).to_proc
      instance_eval(&block) if block_given?
    end

  end

end
