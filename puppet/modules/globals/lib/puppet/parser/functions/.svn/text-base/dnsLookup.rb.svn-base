# Ruby function adding a dnsLookup function to Puppet

# Thanks to Jason Hancock
# http://geek.jasonhancock.com/2011/04/20/doing-a-dns-lookup-inside-your-puppet-manifest/

# does a DNS lookup and returns an array of strings of the results
 
require 'resolv'
 
module Puppet::Parser::Functions
    newfunction(:dnsLookup, :type => :rvalue) do |args|
        result = []
        result = Resolv.new.getaddresses(args[0])
        return result
    end
end

