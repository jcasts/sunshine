class Settler

  class Tpkg < Dependency

    self.sudo = true

    def initialize(dependency_lib, name, options={}, &block)
      super(dependency_lib, name, options) do
        pkg_name = @pkg.dup
        pkg_name << "-#{options[:version]}" if options[:version]
        pkg_name << "-#{options[:rel]}" if options[:rel]
        pkg_name << "-#{options[:arch]}" if options[:arch]

        install    "tpkg -n -i #{pkg_name}"
        uninstall  "tpkg -n -r #{pkg_name}"
        check_test "tpkg -q #{@pkg} | grep -c #{@pkg}", "-ge 1"

        requires(*options[:require].to_a) if options[:require]

        instance_eval(&block) if block_given?
      end
    end


    private

    def run_command(command, options={})
      @dependency_lib.install 'ruby', options if
        @dependency_lib.exist?('ruby')

      @dependency_lib.install 'rubygems', options if
        @dependency_lib.exist?('rubygems')

      @dependency_lib.install 'tpkg', options if
        @dependency_lib.exist?('tpkg')

      super
    end
  end
end
