##
# Defines Sunshine deploy server dependencies.

#class Sunshine::Dependencies < Settler
Sunshine.dependencies.instance_eval do

  apt 'svn', :pkg => 'subversion'
  yum 'svn', :pkg => 'subversion'

  apt 'git', :pkg => 'git-core'
  yum 'git', :pkg => 'git-core'

  apt 'rsync'
  yum 'rsync'

  yum 'httpd-devel'

  apt 'apache2', :pkg => 'apache2-mpm-prefork'
  yum 'apache2', :pkg => 'httpd', :requires => 'httpd-devel'

  apt 'nginx'
  yum 'nginx'

  apt 'logrotate'
  yum 'logrotate'

  apt 'ruby', :pkg => 'ruby-full'
  yum 'ruby'

  apt 'ruby-devel', :pkg => 'ruby-dev'
  yum 'ruby-devel'

  apt 'irb'
  yum 'irb', :pkg => 'ruby-irb'

  apt 'rubygems', :version => '1.3.5' do
    requires 'ruby', 'ruby-devel'
  end
  yum 'rubygems', :version => '1.3.5' do
    requires 'ruby', 'ruby-devel'
  end

  apt 'logrotate'
  yum 'logrotate'

  apt 'curl-devel', :pkg => 'libcurl-dev'
  yum 'curl-devel'

  apt 'libxml2-devel', :pkg => 'libxml2-dev'
  yum 'libxml2-devel'

  apt 'libxslt-devel', :pkg => 'libxslt-dev'
  yum 'libxslt-devel'

  apt 'sqlite', :pkg => 'sqlite3'
  yum 'sqlite'

  apt 'sqlite-devel', :pkg => 'libsqlite3-dev'
  yum 'sqlite-devel'


  ##
  # Define phusion passenger dependencies

  gem 'passenger', :version => ">=2.2.11"

  dependency 'passenger-nginx' do
    requires 'passenger'

    install do |shell, sudo|

      shell.call 'passenger-install-nginx-module --auto --auto-download',
                                        :sudo => true do |stream, data, inn|

        if data =~ /Please specify a prefix directory \[(.*)\]:/

          dir = $1
          inn.puts dir

          required_dirs = [
            File.join(dir, 'fastcgi_temp'),
            File.join(dir, 'proxy_temp')
          ]

          shell.call "mkdir -p #{required_dirs.join(" ")}", :sudo => true

          err_log = File.join(dir, "logs/error.log")
          shell.call "touch #{err_log} && chmod a+rw #{err_log}", :sudo => true
        end
      end
    end


    check do |shell, sudo|
      shell.call("nginx -V 2>&1") =~ /gems\/passenger-\d+(\.\d+)+\/ext\/nginx/
    end
  end


  dependency 'passenger-apache' do
    requires 'passenger', 'apache2'

    install do |shell, sudo|
      shell.call 'passenger-install-apache2-module --auto', :sudo => true
    end

    check do |shell, sudo|
      passenger_dir = Sunshine::Server.passenger_root shell
      passenger_mod = File.join passenger_dir, 'ext/apache2/mod_passenger.so'

      shell.call("test -f #{passenger_mod} && apachectl -v")
    end
  end


  ##
  # Define gems used by Sunshine

  gem 'bundler', :version => ">=0.9"

  gem 'isolate', :version => ">=1.3.0"

  gem 'rake', :version => ">=0.8"

  gem 'geminstaller', :version => ">=0.5"

  gem 'unicorn', :version => ">=0.9"

  gem 'rainbows', :version => ">=0.90.2"

  gem 'ar_mailer', :version => ">=1.5.0"

  gem 'haml'

  gem 'daemons'

end
