module Sunshine

  module StartCommand

    def self.exec argv, config
      
    end


    def self.parse_args argv
      DefaultCommand.parse_remote_args(argv) do |opt|
        opt.banner = <<-EOF

Usage: #{opt.program_name} start app_name [more names...] [options]

Arguments:
    app_name     Name of the application to start.
        EOF

        opt.on('-f', '--force',
               'Restart apps that are running.') do
          options['force'] = true
        end
      end
    end
  end
end

