module Sunshine

  ##
  # A simple namespaced grouping of cron jobs that can be written
  # to a deploy server.

  class Crontab

    attr_reader :cron_jobs

    def initialize name
      @name = name
      @cron_jobs = Hash.new{|hash, key| hash[key] = []}
    end


    ##
    # Add a cron command to a given namespace:
    #   crontab.add "logrotote", "00 * * * * /usr/sbin/logrotate"

    def add namespace, cron_cmd
      @cron_jobs[namespace] << cron_cmd unless @cron_jobs.include?(cron_cmd)
    end


    ##
    # Build the crontab by replacing preexisting cron jobs and adding new ones.

    def build crontab=""
      @cron_jobs.each do |namespace, cron_arr|
        start_id = "# sunshine #{@name}:#{namespace}:begin"
        end_id = "# sunshine #{@name}:#{namespace}:end"

        crontab.sub!(/#{start_id}.*#{end_id}/m, "")

        cron_str = "\n#{start_id}\n#{cron_arr.join("\n")}\n#{end_id}\n\n"

        crontab << cron_str
      end

      crontab
    end


    ##
    # Write the crontab on the given deploy_server

    def write! deploy_server
      crontab = deploy_server.call("crontab -l") rescue ""
      crontab = build crontab.strip!

      deploy_server.call("echo '#{crontab.gsub(/'/){|s| "'\\''"}}' | crontab")

      crontab
    end
  end
end
