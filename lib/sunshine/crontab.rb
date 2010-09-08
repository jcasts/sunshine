module Sunshine

  ##
  # A simple namespaced grouping of cron jobs that can be read and written
  # to a shell.

  class Crontab

    attr_reader :name, :shell

    def initialize name, shell
      @name  = name
      @shell = shell
      @jobs  = nil
    end


    ##
    # Access the jobs hash. Equivalent to:
    #   crontab.jobs[key]

    def [] key
      self.jobs[key]
    end


    ##
    # Set a value in the jobs hash.Equivalent to:
    #   crontab.jobs[key] = value

    def []= key, value
      self.jobs[key] = value
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
        cron_job = cron_job.join("\n") if Array === cron_job
        crontab  = delete_jobs crontab, namespace

        next if cron_job.nil? || cron_job.empty?

        start_id, end_id = get_job_ids namespace
        cron_str = "\n#{start_id}\n#{cron_job.chomp}\n#{end_id}\n\n"

        crontab << cron_str
      end

      crontab
    end


    ##
    # Remove all cron jobs that reference crontab.name.

    def delete!
      crontab = read_crontab
      crontab = delete_jobs crontab

      write_crontab crontab

      crontab
    end


    ##
    # Write the crontab on the given shell

    def write!
      return unless modified?

      crontab = read_crontab
      crontab = delete_jobs crontab
      crontab = build crontab

      write_crontab crontab

      crontab
    end


    ##
    # Checks if the crontab was modified for crontab.name.

    def modified?
      !@jobs.nil?
    end


    ##
    # Load a crontab string and parse out jobs related to crontab.name.
    # Returns a hash of namespace/jobs pairs.

    def parse string
      jobs = Hash.new{|hash, key| hash[key] = Array.new}

      namespace = nil

      string.each_line do |line|
        if line =~ /^# sunshine #{@name}:(.*):begin/
          namespace = $1
          next
        elsif line =~ /^# sunshine #{@name}:#{namespace}:end/
          namespace = nil
        end

        if namespace
          line = line.strip
          jobs[namespace] << line unless line.empty?
        end
      end

      jobs unless jobs.empty?
    end


    ##
    # Returns the shell's crontab as a string

    def read_crontab
      @shell.call("crontab -l") rescue ""
    end


    private

    ##
    # Write the string to the shell's crontab.

    def write_crontab content
      @shell.call("echo '#{content.gsub(/'/){|s| "'\\''"}}' | crontab")
    end


    ##
    # Deletes all jobs of a given namespace in a crontab string.

    def delete_jobs crontab, namespace=nil
      start_id, end_id = get_job_ids namespace

      crontab.gsub!(/^#{start_id}$(.*?)^#{end_id}$\n*/m, "")

      crontab
    end


    ##
    # Returns the cronjob begin and end flags.

    def get_job_ids namespace=nil
      namespace ||= "[^\n]*"

      start_id = "# sunshine #{@name}:#{namespace}:begin"
      end_id = "# sunshine #{@name}:#{namespace}:end"

      return start_id, end_id
    end
  end
end
