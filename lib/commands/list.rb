module Sunshine

  module ListCommand

    def self.exec argv, config
    end


    def self.parse_args argv
      DefaultCommand.parse_remote_args(argv) do |opt|
        opt.banner = <<-EOF

Usage: #{opt.program_name} list app_name [more names...] [options]

Arguments:
    app_name      Name of an application to list.
        EOF

        opt.on('-i', '--installed',
               'Check if app is installed. See also "sunshine add/rm".') do
          options['return'] = :bool
        end

        opt.on('-s', '--status',
               'Check if an app is running.') do
          options['return'] = :status
        end

        opt.on('-d', '--details',
               'Get details about the deployed apps.') do
          options['return'] = :details
        end

        opt.on('-h', '--health [STATUS]', [:on, :off],
               'Set or get the healthcheck status (on, off).') do |status|
          options['health'] = status
          options['return'] = :health
        end
      end
    end
  end
end
