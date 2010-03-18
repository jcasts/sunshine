module Sunshine

  ##
  # A simple namespaced grouping of cron jobs that can be written
  # to a deploy server.

  class Crontab

    attr_reader :name, :shell

    def initialize name, shell
      @name  = name
      @shell = shell
      @jobs  = nil
    end


    ##
    # Get the jobs matching this crontab. Loads them from the crontab
    # if @jobs hasn't been set yet.

    def jobs
      @jobs ||= parse read_crontab
    end


    ##
    # Build the crontab by replacing preexisting cron jobs and adding new ones.

    def build crontab=""
      crontab.strip!

      jobs.each do |namespace, cron_job|
        crontab = delete_jobs crontab, namespace

        start_id, end_id = get_job_ids namespace
        cron_str = "\n#{start_id}\n#{cron_job.chomp}\n#{end_id}\n\n"

        crontab << cron_str
      end

      crontab
    end


    ##
    # Remove all cron jobs that reference crontab.name

    def delete!
      crontab = read_crontab
      crontab = delete_jobs crontab

      write_crontab crontab

      crontab
    end


    ##
    # Write the crontab on the given shell

    def write!
      crontab = read_crontab
      crontab = delete_jobs crontab
      crontab = build crontab

      write_crontab crontab

      crontab
    end


    ##
    # Load a crontab string and parse out jobs related to crontab.name.
    # Returns a hash of namespace/jobs pairs.

    def parse string
      jobs = Hash.new

      namespace = nil

      string.each_line do |line|
        if line =~ /^# sunshine #{@name}:(.*):begin/
          namespace = $1
          next
        elsif line =~ /^# sunshine #{@name}:#{namespace}:end/
          namespace = nil
        end

        if namespace
          jobs[namespace] ||= String.new
          jobs[namespace] << line
        end
      end

      jobs
    end


    ##
    # Returns the shell's crontab as a string

    def read_crontab
      @shell.call("crontab -l") rescue ""
    end


    private

    def write_crontab content
      @shell.call("echo '#{content.gsub(/'/){|s| "'\\''"}}' | crontab")
    end


    def delete_jobs crontab, namespace=nil
      start_id, end_id = get_job_ids namespace

      crontab.gsub!(/^#{start_id}$(.*?)^#{end_id}$\n*/m, "")

      crontab
    end


    def get_job_ids namespace=nil
      namespace ||= "[^\n]*"

      start_id = "# sunshine #{@name}:#{namespace}:begin"
      end_id = "# sunshine #{@name}:#{namespace}:end"

      return start_id, end_id
    end
  end
end
