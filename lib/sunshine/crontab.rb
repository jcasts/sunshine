module Sunshine

  class Crontab

    def initialize name
      @name = name
      @cron_jobs = Hash.new{|hash, key| hash[key] = []}
    end


    ##
    # Add a cron command to a given namespace

    def add namespace, cron_cmd
      @cron_jobs[namespace] << cron_cmd unless @cron_jobs.include?(cron_cmd)
    end


    ##
    # Write the crontab on the given deploy_server

    def write! deploy_server
      crontab = deploy_server.run("crontab -l") rescue ""
      crontab.strip!
      @cron_jobs.each do |namespace, cron_arr|
        start_id = "# sunshine #{@name}:#{namespace}:begin"
        end_id = "# sunshine #{@name}:#{namespace}:end"

        crontab.sub!(/#{start_id}.*#{end_id}/m, "")

        cron_str = "\n#{start_id}\n#{cron_arr.join("\n")}\n#{end_id}\n\n"

        crontab << cron_str
      end
      deploy_server.run("echo '#{crontab.gsub(/'/){|s| "'\\''"}}' | crontab")
      crontab
    end
  end
end
