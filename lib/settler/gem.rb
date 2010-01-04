class Settler

  class Gem < Dependency

    def initialize(dependency_lib, name, options={}, &block)
      super(dependency_lib, name, options) do
        version = options[:version] ? " --version '#{options[:version]}'" : ""
        source = if options[:source]
          " --source #{options[:source]} --source http://gemcutter.org"
        end
        install_opts = " --no-ri --no-rdoc"
        if options[:opts]
          install_opts = "#{install_opts} -- #{options[:opts]}"
        end
        install "sudo gem install #{@pkg}#{version}#{source}#{install_opts}"
        uninstall "sudo gem uninstall #{@pkg}#{version}"
        check "gem list #{@pkg} -i#{version}"
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
      @dependency_lib.install 'ruby-devel', options if
        @dependency_lib.exist?('ruby-devel')
      super
    end

  end

end
