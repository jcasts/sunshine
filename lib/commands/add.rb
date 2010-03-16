module Sunshine

  ##
  # Registers a path as a sunshine application for control via sunshine.
  #
  # Usage: sunshine add app_path [more paths...] [options]
  #
  # Arguments:
  #     app_path    Path to the application to add.
  #                 A name may be assigned to the app by specifying name:path.
  #                 By default: name = File.basename app_path
  #
  # Options:
  #     -f, --format FORMAT        Set the output format (txt, yml, json)
  #     -u, --user USER            User to use for remote login. Use with -r.
  #     -r, --remote svr1,svr2     Run on one or more remote servers.
  #     -v, --verbose              Run in verbose mode.

  class AddCommand < ListCommand

    ##
    # Takes an array and a hash, runs the command and returns:
    #   true: success
    #   false: failed
    #   exitcode:
    #     code == 0: success
    #     code != 0: failed
    # and optionally an accompanying message.

    def self.exec names, config
      apps_hash  = parse_app_paths(*names)

      output = exec_each_server config do |shell|
        server_command = new(shell)
        results        = server_command.add apps_hash

        self.save_list server_command.app_list, shell

        results
      end

      return output
    end


    ##
    # Takes an array of app path definitions and returns a hash:
    #   parse_app_paths "myapp:/path/to/app", "/path/to/otherapp"
    #   #=> {'myapp' => '/path/to/app', 'otherapp' => '/path/to/otherapp'}

    def self.parse_app_paths(*app_paths)
      apps_hash = {}
      app_paths.each do |path|
        name, path = path.split(":") if path.include?(":")
        name ||= File.basename path

        apps_hash[name] = path
      end
      apps_hash
    end


    ##
    # Add a registered app on a given deploy server

    def add apps_hash
      response_for_each(*apps_hash.keys) do |name|
        path = apps_hash[name]
        test_dir = @shell.call("test -d #{path}") rescue false

        raise "'#{path}' is not a directory." unless test_dir

        @app_list[name] = path
      end
    end


    ##
    # Parses the argv passed to the command

    def self.parse_args argv

      parse_remote_args(argv) do |opt, options|
        opt.banner = <<-EOF

Usage: #{opt.program_name} add app_path [more paths...] [options]

Arguments:
    app_path      Path to the application to add.
                  A name may be assigned to the app by specifying name:app_path.
                  By default: name = File.basename app_path
        EOF
      end
    end
  end
end
