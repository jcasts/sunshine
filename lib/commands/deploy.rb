module Sunshine

  ##
  # Run a sunshine deploy script.
  #
  # Usage: sunshine deploy [deploy_file] [options]
  #
  # Arguments:
  #     deploy_file     Load a deploy script or app path. Defaults to ./Sunshine
  #
  # Options:
  #     -l, --level LEVEL         Set trace level. Defaults to info.
  #     -e, --env DEPLOY_ENV      Sets the deploy env. Defaults to development.
  #     -a, --auto                Non-interactive - automate or fail.
  #         --no-trace            Don't trace any output.

  module DeployCommand

    ##
    # Takes an array and a hash, runs the command and returns:
    #   true: success
    #   false: failed
    #   exitcode:
    #     code == 0: success
    #     code != 0: failed
    # and optionally an accompanying message.

    def self.exec deploy_file, config
      deploy_file = deploy_file.first if Array === deploy_file

      deploy_file = File.join(deploy_file, "Sunshine") if
        deploy_file && File.directory?(deploy_file)

      deploy_file ||= "Sunshine"
      puts "Running #{deploy_file}"

      get_file_data deploy_file

      require deploy_file

      return true
    end


    def self.get_file_data deploy_file
      return if defined?(Sunshine::DATA)
      data_marker = "__END__\n"
      line = nil

      #DATA = File.open(deploy_file, 'r')
      Sunshine.const_set("DATA", File.open(deploy_file, 'r'))
      #global_const_set "DATA", File.open(deploy_file, 'r')

      until line == data_marker || Sunshine::DATA.eof?
        line = Sunshine::DATA.gets
      end
    end


    ##
    # Parses the argv passed to the command

    def self.parse_args argv
      options = {'trace' => true}

      opts = DefaultCommand.opt_parser do |opt|
        opt.banner = <<-EOF

Usage: #{opt.program_name} deploy [deploy_file] [options]

Arguments:
    deploy_file     Load a deploy script or app path. Defaults to ./Sunshine
        EOF

        opt.separator nil
        opt.separator "Options:"

        opt.on('-l', '--level LEVEL',
               'Set trace level. Defaults to info.') do |value|
          options['level'] = value
        end

        opt.on('-e', '--env DEPLOY_ENV',
               'Sets the deploy env. Defaults to development.') do |value|
          options['deploy_env'] = value
        end

        opt.on('-a', '--auto',
               'Non-interactive - automate or fail.') do
          options['auto'] = true
        end

        opt.on('--no-trace',
               "Don't trace any output.") do
          options['trace'] = false
        end
      end

      opts.parse! argv

      options
    end
  end
end
