module Sunshine

  ##
  # Run one or more sunshine scripts.
  #
  # Usage: sunshine run [options] [run_file] ...
  #
  # Arguments:
  #     run_file     Load a script or app path. Defaults to ./Sunshine
  #
  # Options:
  #     -l, --level LEVEL         Set trace level. Defaults to info.
  #     -e, --env DEPLOY_ENV      Sets the deploy env. Defaults to development.
  #     -a, --auto                Non-interactive - automate or fail.
  #         --no-trace            Don't trace any output.

  class RunCommand < DefaultCommand

    ##
    # Takes an array and a hash, runs the command and returns:
    #   true: success
    #   false: failed
    #   exitcode:
    #     code == 0: success
    #     code != 0: failed
    # and optionally an accompanying message.

    def self.exec run_files, config

      run_files.each do |run_file|

        run_file = run_file_from run_file

        with_load_path File.dirname(run_file) do

          puts "Running #{run_file}"

          get_file_data run_file

          require run_file
        end
      end

      return true
    end


    ##
    # Tries to infer what run file to used based on a given path:
    #   run_file_from "path/to/some/dir"
    #     #=> "path/to/some/dir/Sunshine"
    #   run_file_from nil
    #     #=> "Sunshine"
    #   run_file_from "path/to/run_script.rb"
    #     #=> "path/to/run_script.rb"

    def self.run_file_from run_file
      run_file = File.join(run_file, "Sunshine") if
        run_file && File.directory?(run_file)

      run_file ||= "Sunshine"

      File.expand_path run_file
    end


    ##
    # Adds a directory to the ruby load path and runs the passed block.
    # Useful for scripts to be able to reference their own dirs.

    def self.with_load_path path
      path = File.expand_path path

      # TODO: Find a better way to make file path accessible to App objects.
      Sunshine.send :remove_const, "PATH" if defined?(Sunshine::PATH)
      Sunshine.const_set "PATH", path

      added = unless $:.include? path
                $: << path && true
              end

      yield

      Sunshine.send :remove_const, "PATH"

      $:.delete path if added
    end


    ##
    # Returns file data in a run file as a File IO object.

    def self.get_file_data run_file
      # TODO: Find a better way to make file data accessible to App objects.
      Sunshine.send :remove_const, "DATA" if defined?(Sunshine::DATA)
      data_marker = "__END__\n"
      line = nil

      Sunshine.const_set("DATA", File.open(run_file, 'r'))

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

Usage: #{opt.program_name} run [options] [run_file] ...

Arguments:
    run_file     Load a script or app path. Defaults to ./Sunshine
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
