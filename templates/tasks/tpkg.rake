namespace :tpkg do
  desc "Run tpkg install/uninstall from a conf file."
  task :run do

    tpkg_file   = ENV['conf']
    tpkg_file ||= 'config/tpkginstaller.conf'

    build = `uname -p`.strip

    File.readlines(tpkg_file).each do |tpkg|
      tpkg   = tpkg.strip.gsub("$proc", build)
      action = tpkg.slice!(0..1)

      success = if action == "+"
        puts "## Installing tpkg: #{tpkg}"
        system "tpkg -n -u http://tpkg/tpkg/#{tpkg}.tpkg"

      elsif action == "-"
        puts "## Removing tpkg: #{tpkg}"
        system "tpkg -n -r #{tpkg}"

      else
        true
      end

      raise "Error running tpkg: #{action}#{tpkg}" unless success
    end
  end
end
