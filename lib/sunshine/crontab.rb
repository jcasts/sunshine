module Sunshine

  class Crontab

    START_IDENTIFIER = "# sunshine start"
    END_IDENTIFIER = "# sunshine end"

    def initialize(name)
      @name = name
      @cron_jobs = Hash.new{|hash, key| hash[key] = []}
    end

    def add(namespace, cron_cmd)
      @cron_jobs[namespace] << cron_cmd unless @cron_jobs.include?(cron_cmd)
    end

    def write!(cmd)
      crontab = cmd.call("crontab -l") rescue ""
      crontab.strip!
      @cron_jobs.each do |namespace, cron_cmd|
        start_id = "#{START_IDENTIFIER} #{@name}:#{namespace}\n"
        end_id = "#{END_IDENTIFIER} #{@name}:#{namespace}\n"
        cron_str = "\n#{start_id}#{cron_cmd}\n#{end_id}\n"
        crontab.sub!(/#{start_id}.*#{end_id}/m, "")
        crontab << cron_str
      end
      cmd.call("echo '#{crontab.gsub(/'/){|s| "'\\''"}}' | crontab")
      crontab
    end

  end

end
