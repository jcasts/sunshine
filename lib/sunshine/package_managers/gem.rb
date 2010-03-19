module Sunshine

  ##
  # The Gem dependency class supports most of rubygem's installation features:
  #
  #   dependency_lib.instance_eval do
  #     gem "rdoc", :version => '~>0.8',
  #                 :source  => 'http://gemcutter.org',
  #                 :opts    => '--use-lib blah' # Anything after --
  #   end
  #
  # See the Dependency class for more info.

  class Gem < Dependency

    self.sudo = true


    def initialize(name, options={}, &block)
      super(name, options) do
        version = options[:version] ? " --version '#{options[:version]}'" : ""

        source = if options[:source]
          " --source #{options[:source]} --source http://gemcutter.org"
        end

        install_opts = " --no-ri --no-rdoc"
        if options[:opts]
          install_opts = "#{install_opts} -- #{options[:opts]}"
        end

        install   "gem install #{@pkg}#{version}#{source}#{install_opts}"
        uninstall "gem uninstall #{@pkg}#{version}"
        check     "gem list #{@pkg} -i#{version}"

        requires(*options[:require].to_a) if options[:require]

        instance_eval(&block) if block_given?
      end
    end


    private

    def run_command(command, options={})
      if @dependency_lib
        @dependency_lib.install 'rubygems', options if
          @dependency_lib.exist?('rubygems')
      end

      super
    end
  end
end
