namespace :app do
  desc "Generate static files.  (eg. error pages, css from sass, bundles, etc.)"
  task :generate_static_files =>
    [:generate_css_files, :generate_bundles, :generate_error_pages]

  ##
  # Error page generation will generate bundles, as long as they're in the
  # main application layout and we're still using bundle-fu or smurf.

  desc "Generate bundles for javascript/css"
  task :generate_bundles => :generate_error_pages


  desc "Generate css from sass"
  task :generate_css_files => :environment do
    Sass::Plugin.update_stylesheets
  end


  desc "Generate static error pages."
  task :generate_error_pages => :environment do
    require 'action_controller/integration'

    app = ActionController::Integration::Session.new

    [404, 500].each do |code|
      app.get("/pages/error_#{code}")
      File.open("public/#{code}.html", 'w'){|file| file << app.response.body}
    end
  end
end


require 'rake/rdoctask'

unless Rake::TaskManager.method_defined? :remove_task
  module Rake::TaskManager
    # HACK: used by documentation.rake and testing.rake
    def remove_task name
      @tasks.delete name.to_s
    end
  end
end


##
# HACK: The built-in Rails doc:app task doesn't provide a good way to
# get extra RDoc files and stuff into the build, so we kill it and
# write our own, snucka.

rdoc_tasks = %w(doc:app doc:reapp redoc:app doc:clobber_app doc/app/index.html)

rdoc_tasks.each do |task|
 Rake.application.remove_task task
end


Rake::RDocTask.new "doc:app" do |rdoc|
  rdoc.title    = "ng2"
  rdoc.rdoc_dir = "doc/app"

  rdoc.options.concat %w(--line-numbers --charset utf-8)

  rdoc.rdoc_files.include "doc/*.rdoc"
  rdoc.rdoc_files.include "{app,lib}/**/*.rb"
end
