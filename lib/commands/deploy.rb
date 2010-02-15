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

  class DeployCommand < DefaultCommand

    ##
    # Takes an array and a hash, runs the command and returns:
    #   true: success
    #   false: failed
    #   exitcode:
    #     code == 0: success
    #     code != 0: failed
    # and optionally an accompanying message.

    def self.exec deploy_files, config

      deploy_files.each do |deploy_file|

        deploy_file = deploy_file_from deploy_file

        with_load_path File.dirname(deploy_file) do

          puts "Running #{deploy_file}"

          get_file_data deploy_file

          require deploy_file
        end
      end

      return true
    end


    ##
    # Tries to infer what deploy file to used based on a given path:
    #   deploy_file_from "path/to/some/dir"
    #     #=> "path/to/some/dir/Sunshine"
    #   deploy_file_from nil
    #     #=> "Sunshine"
    #   deploy_file_from "path/to/deploy_script.rb"
    #     #=> "path/to/deploy_script.rb"

    def self.deploy_file_from deploy_file
      deploy_file = File.join(deploy_file, "Sunshine") if
        deploy_file && File.directory?(deploy_file)

      deploy_file ||= "Sunshine"

      File.expand_path deploy_file
    end


    ##
    # Adds a directory to the ruby load path and runs the passed block.
    # Useful for deploy scripts to be able to reference their own dirs.

    def self.with_load_path path
      path = File.expand_path path

      added = unless $:.include? path
                $: << path && true
              end

      yield

      $:.delete path if added
    end


    ##
    # Returns file data in a deploy file as a File IO object.

    def self.get_file_data deploy_file
      # TODO: Find a better way to make file data accessible to App objects.
      Sunshine.send :remove_const, "DATA" if defined?(Sunshine::DATA)
      data_marker = "__END__\n"
      line = nil

      Sunshine.const_set("DATA", File.open(deploy_file, 'r'))

      until line == data_marker || Sunshine::DATA.eof?
        line = Sunshine::DATA.gets
      end
    end


    ##
    # Parses the argv passed to the command

    def self.parse_args argv
      options = {'trace' => true}

      opts = opt_parser(options) do |opt|
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
