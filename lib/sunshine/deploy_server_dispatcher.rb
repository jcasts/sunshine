module Sunshine

  class DeployServerDispatcher

    def initialize(*deploy_servers)
      @deploy_servers = []
      self.add(*deploy_servers)
    end


    ##
    # Append a deploy server

    def <<(deploy_server)
      deploy_server = DeployServer.new(deploy_server) unless
        DeployServer === deploy_server
      @deploy_servers.push(deploy_server) unless self.exist?(deploy_server)
    end


    ##
    # Get the deploy server at a given index

    def [](index)
      @deploy_servers[index]
    end


    ##
    # Add a list of deploy servers. Supports strings (user@server)
    # and DeployServer objects

    def add(*arr)
      arr.each do |ds|
        self << ds
      end
    end


    ##
    # Iterate over all deploy servers

    def each(&block)
      warn_if_empty
      @deploy_servers.each(&block)
    end


    ##
    # Find deploy servers matching the passed requirements
    # Returns a DeployServerDispatcher object
    #   find :user => 'db'
    #   find :host => 'someserver.com'
    #   find :role => :web

    def find(query=nil)
      return self if query.nil? || query == :all
      results = @deploy_servers.select do |ds|
        next unless ds.user == query[:user] if query[:user]
        next unless ds.host == query[:host] if query[:host]
        next unless ds.roles.include?(query[:role]) if query[:role]
        true
      end
      self.class.new(*results)
    end


    ##
    # Returns true if the dispatcher has a matching deploy_server

    def exist?(deploy_server)
      @deploy_servers.include? deploy_server
    end


    ##
    # Checks if the dispatcher has any deploy servers

    def empty?
      @deploy_servers.empty?
    end


    ##
    # Returns the number of deploy servers

    def length
      @deploy_servers.length
    end


    ##
    # Forwarding methods to deploy servers

    def connect(*args, &block)
      call_each_method :connect, *args, &block
    end

    def disconnect(*args, &block)
      call_each_method :disconnect, *args, &block
    end

    def symlink(*args, &block)
      call_each_method :symlink, *args, &block
    end

    def upload(*args, &block)
      call_each_method :upload, *args, &block
    end

    def make_file(*args, &block)
      call_each_method :make_file, *args, &block
    end

    def run(*args, &block)
      call_each_method :run, *args, &block
    end

    alias call run


    private

    def call_each_method(method_name, *args, &block)
      self.each do |deploy_server|
        deploy_server.send(method_name, *args, &block)
      end
    end

    def warn_if_empty
      return unless self.empty?
      Sunshine.logger.warn :deploy_servers,
        "No deploy servers are configured. The action will not be executed."
    end
  end
end
