namespace :common do
  desc "Create a file based on a template."
  task :template => [:environment, :template_without_environment]

  desc "Create a file based on a template, without loading the environment."
  task :template_without_environment do
    SOURCE  = ENV['source']
    TARGET  = ENV['target']

    raise "Usage: #{$0} source=source_file target=target_file" unless
      SOURCE and TARGET

    require 'erb'
    begin
      File.open(TARGET, 'w') do |f|
        f.write ERB.new(File.read(SOURCE), nil, '-').result
      end
    rescue => e
      raise "ERROR creating template '#{TARGET}': #{e}"
    end
  end

  desc "Update the crontab file."
  task :cron do
    require 'tempfile'
    require 'whenever'

    application = ENV['APPLICATION'] || File.basename(Dir.pwd)

    Whenever::CommandLine.execute(:update => true, :identifier => application)
  end
end
