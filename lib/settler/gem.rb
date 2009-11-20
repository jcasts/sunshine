class Settler

  class Gem < Dependency

    register_with_settler

    def initialize(dependency_lib, name, options={}, &block)
      super(dependency_lib, name, options) do
        version = options[:version] ? " --version '#{options[:version]}'" : ""
        install "gem install #{@name}#{version}"
        uninstall "gem uninstall #{@name}#{version}"
        check "gem list #{@name} -i#{version}"
        requires(*options[:require].to_a) if options[:require]
        instance_eval(&block) if block_given?
      end
    end

  end

end
