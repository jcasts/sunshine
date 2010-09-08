module Sunshine

  ##
  # Runs a given script of all specified sunshine apps.
  #
  # Usage: sunshine script script_name [options] app_name [more names...]
  #
  # Arguments:
  #     script_name  Name of the script to run.
  #     app_name     Name of the application to run script for.
  #
  # Options:
  #     -f, --format FORMAT        Set the output format (txt, yml, json)
  #     -u, --user USER            User to use for remote login. Use with -r.
  #     -r, --remote svr1,svr2     Run on one or more remote servers.
  #     -v, --verbose              Run in verbose mode.

  class ScriptCommand < ListCommand

    ##
    # Takes an array and a hash, runs the command and returns:
    #   true: success
    #   false: failed
    #   exitcode:
    #     code == 0: success
    #     code != 0: failed
    # and optionally an accompanying message.

    def self.exec names, config
      script_name = names.delete_at(0)

      output = exec_each_server config do |shell|
        new(shell).script(script_name, names)
      end

      return output
    end


    ##
    # Run specified script for apps.

    def script name, app_names
      each_app(*app_names) do |server_app|
        server_app.run_script name
      end
    end


    ##
    # Parses the argv passed to the command

    def self.parse_args argv
      parse_remote_args(argv) do |opt, options|
        opt.banner = <<-EOF

Usage: #{opt.program_name} script script_name [options] app_name [more names...]

Arguments:
    script_name  Name of the script to run.
    app_name     Name of the application to run script for.
        EOF
      end
    end
  end
end

