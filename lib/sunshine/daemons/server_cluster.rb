module Sunshine

  ##
  # The ServerCluster is simply a fancy Array that conveniently forwards
  # some method calls to each server in the array, namely:
  # Server#setup, Server#start, Server#stop, Server#restart,
  # Server#has_setup?, Server#status.

  class ServerCluster < Array

    ##
    # ServerClusters get initialized just like any server class with the
    # additional svr_class (Unicorn, Thin, Mongrel) and the number of
    # server instances you would like:
    #
    #   ServerCluster.new Mongrel, 3, app, :port => 5000
    #   #=> [<# mongrel_5000 >, <# mongrel_5001 >, <# mongrel_5002 >]
    #
    # ServerClusters can also be created from any Server class:
    #
    #   Mongrel.new_cluster 3, app, :port => 5000

    def initialize svr_class, count, app, options={}
      count.times do |num|
        port = (options[:port] || 80) + num
        name = (options[:name] || svr_class.short_name) + ".#{port}"

        self << svr_class.new(app, options.merge(:name => name, :port => port))
      end
    end


    [:setup, :start, :stop, :restart].each do |method|
      define_method method do
        each{|server| server.send method }
      end
    end


    [:has_setup?, :status].each do |method|
      define_method method do
        each{|server| return false unless server.send method}
        true
      end
    end
  end
end
