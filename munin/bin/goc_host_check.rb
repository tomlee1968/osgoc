#!/usr/bin/env ruby

# goc_host_check.rb -- modify the Munin configuration based on node status
# Tom Lee <thomlee@iu.edu>
# Begun 2017/02/25 based on goc-host-check.pl
# Last modified 2018/01/08

# Look at the network and compare what we find with the Munin
# conf.yaml file. Add new entries, remove old entries, and
# disable/enable existing entries as needed. (Currently it just prints
# discrepancies, because I'm afraid of having it make changes
# automatically.)

# The older goc-host-check.pl suffers from nomenclature creep: the two
# networks are called public/private, internal/external, and
# local/global. I'm going to stick to public/private here.

###############################################################################
# Requires

require 'rubygems'
require 'forwardable'
require 'ipaddr'
require 'net/ldap'
require 'optparse'
require 'ping'
require 'resolv'
require 'set'
require 'thread'
require 'yaml'

###############################################################################
# Settings

# Program name
$PROG_NAME = 'goc_host_check.rb'

# Program version
$PROG_VERSION = '0.1'

# Program release
$PROG_RELEASE = 'alpha'

# Munin main directory
$MUNIN_DIR = '/usr/local/munin'

# Munin config file
$MUNIN_CONFIG = "#{$MUNIN_DIR}/etc/conf.yaml"

# Config file for this script
$GHC_CONFIG = "#{$MUNIN_DIR}/etc/goc_host_check_conf.yaml"

# Munin update lock file -- munin-update puts this here when it runs
$MUNIN_UPDATE_LOCK = '/var/run/munin/munin-update.lock'

# Network information
$NETINFO =
  {
  'loopback' =>
  {
    'domains' =>
    [
     'localdomain',
    ],
    'ipranges' =>
    [
     (IPAddr.new '127.0.0.0/8'),
     (IPAddr.new '::1/128'),
    ],
  },
  'public' =>
  {
    'domains' =>
    [
     'grid.iu.edu',
     'opensciencegrid.org',
     'uits.indiana.edu',
    ],
    'ipranges' =>
    [
     (IPAddr.new '129.79.53.0/24'),
     (IPAddr.new '2001:18e8:2:6::/64'),
    ],
  },
  'private' =>
  {
    'domains' =>
    [
     'goc',
    ],
    'ipranges' =>
    [
     (IPAddr.new '192.168.96.0/22'),
     (IPAddr.new 'fd2f:6feb:37::/48'),
    ],
  },
}

# LDAP domain for finding LDAP server
$LDAP_DOMAIN = 'goc'

# LDAP base for lookups
$LDAP_BASE = 'dc=goc'

# Set path
ENV['PATH'] = '/sbin:/bin:/usr/sbin:/usr/bin'

###############################################################################
# Classes

class ConfigError < RuntimeError
end

class NetworkError < RuntimeError
end

class HostNet
  # A Host will have one or more of these. It contains the host's
  # network information (main hostname, alternate hostnames, IP
  # addresses, ping results) for one network.

  attr_accessor :label, :main, :alts, :ips, :thread

  def initialize params
    raise ArgumentError.new "Requires a Hash (not a #{params.class})" unless params.kind_of? Hash

    @label = ''
    @main = ''
    @alts = []
    @ips = []
    @thread = nil
    @pinged = false
    @pingok = nil
    [:label, :main, :alts, :ips].each do |param|
      method(param.to_s + '=').call(params[param]) if params.key? param
    end
  end

  def push_alt alt
    @alts = [] unless @alts.kind_of? Array
    @alts.push alt
  end

  def push_ip ip
    @ips = [] unless @ips.kind_of? Array
    ip = IPAddr.new ip unless ip.kind_of? IPAddr
    @ips.push ip
  end

  def pinged?
    return @pinged
  end

  def pinged_ok?
    return @pingok
  end

  def ping params = {}
    # Pings the target specified in the HostNet object. Of course, the
    # target might have more than one IP address, especially given
    # IPv4/IPv6 dual-stacked hosts. This method must figure this out,
    # possibly trying all applicable IP addresses before deciding that
    # the ping has failed. Of course, if the machine this script is
    # running on isn't dual-stacked, don't try using an IP version
    # that isn't supported. When done, set @pinged to true, and set
    # @pingok to true if the ping succeeded (and false if it failed).

    # Find out which of $NETINFO's netlabels this HostNet object's IPs
    # are on. We're going to assume $NETINFO is configured right, and
    # we're going to assume that the LDAP and DNS are configured such
    # that all the remote host's IPs in @ips are on the same network.
    netlabel = nil
    @ips.each do |ip|
      $NETINFO.each do |nl, ni|
        matches = ni['ipranges'].select { |ipr| ipr.include? ip }
        if matches.size > 0
          netlabel = nl
          break
        end
      end
      break if netlabel
    end
    # This would be strange. If this happens, the user should probably
    # configure the target "noping" in the config file.
    if netlabel.nil?
      raise NetworkError.new "Target '#{@main}' has no IPs on any configured network"
    end

    # Process parameters.
    srcips = []
    if params.key? :srcip
      # One thing we're going to have to figure out is what interface
      # or source IP to ping from. If we're given a source IP via this
      # parameter, though, it's suddenly easy. Use that.

      # But make sure it's possible to ping from this source IP -- if
      # it's not within any of the ranges in $NETINFO[netlabel],
      # reject it.
      params[:srcip] = IPAddr.new params[:srcip] unless params[:srcip].kind_of? IPAddr
      matches = $NETINFO[netlabel]['ipranges'].select { |ipr| ipr.include? params[:srcip] }
      if matches.size == 0
        raise NetworkError.new "Target '#{@main}' cannot be reached from specified source IP '#{params[:srcip]}'"
      end
      srcips.push params[:srcip]
    else
      # No source IP was specified, meaning that we'll have to figure
      # it out ourselves. Find all IPs in $myip[netlabel] that are in
      # any of $NETINFO[netlabel]'s IP ranges. We might have to ping
      # all of them.

      $NETINFO[netlabel]['ipranges']. each do |ipr|
        matches = $myip[netlabel]['ips'].select { |ip| ipr.include? ip }
        matches.each { |ip| srcips.push ip }
      end
    end

    count = 1
    if params.key? :count
      count = params[:count]
    end

    timeout = 1
    if params.key? :timeout
      timeout = params[:timeout]
    end

    # Now do the pings. Ping IPv6 addresses preferentially, as it's
    # the future. Only ping IPv4 addresses if they're the only ones
    # available or if all IPv6 addresses have failed to respond.
    srcips.sort! { |a, b| b.family <=> a.family } # ipv4.family == 2; ipv6.family == 10
    srcips.each do |srcip|
      # Figure out whether we have to ping or ping6.
      if srcip.ipv4?
        basecmd = "/bin/ping"
      elsif srcip.ipv6?
        basecmd = "/bin/ping6"
      else
        raise NetworkError.new "Source IP address '#{srcip}' appears to be neither IPv4 nor IPv6 -- protocol not yet supported"
      end
      basecmd += ' -n -q'
      basecmd += " -c #{count} -W #{timeout}"
      # Ping all applicable IPs in the HostNet object.
      @ips.select { |ip| ip.family == srcip.family }.sort { |a, b| b.family <=> a.family }.each do |ip|
        cmd = basecmd + " -I #{srcip} #{ip} >&/dev/null"
        @pingok = system cmd
        @pinged = true
      end
    end
  end
end

class Host
  # In this context a host consists of all network and Munin
  # information we know about it, including its short hostname; its
  # main hostname, alternate hostnames, IP addresses, and ping results
  # for each network it's on; its Munin parameters; etc.

  attr_accessor :short, :flags, :problems, :muninname
  attr_reader :nets, :munin

  def initialize params
    raise ArgumentError.new "Requires a Hash (not a #{params.class})" unless params.kind_of? Hash

    @nets = []
    @munin = {}
    @flags = Set.new
    @problems = Set.new
    [:short, :nets, :munin, :flags].each do |param|
      method(param.to_s + '=').call(params[param]) if params.key? param
    end
    raise ArgumentError.new "Must have a :short, which must be a String" unless @short.kind_of? String
  end

  def net? netlabel
    hostnets = @nets.select { |n| n.label == netlabel }
    if hostnets.empty?
      return false
    else
      return true
    end
  end

  def net netlabel
    hostnets = @nets.select { |n| n.label == netlabel }
    if hostnets.empty?
      newnet = HostNet.new(:label => netlabel)
      @nets.push newnet
      hostnets = [newnet]
    end
    raise ArgumentError.new "Multiple nets with label '#{netlabel}' exist for host '#{@short}'" unless hostnets.size == 1
    return hostnets[0]
  end

  def nets= nets
    raise ArgumentError.new "Requires an Array (not a #{net.class})" unless net.kind_of? Array
    @nets = nets
  end

  def munin= munin
    raise ArgumentError.new "Requires a Hash (not a #{params.class})" unless munin.kind_of? Hash
    @munin = munin
  end

  def push_net net
    raise ArgumentError.new "Requires a HostNet (not a #{net.class})" unless net.kind_of? HostNet
    @nets = [] unless @nets.kind_of? Array
    unless (@nets.select { |n| n.label == net.label }).empty?
      raise ArgumentError.new "A HostNet with label '#{net.label}' already exists for host '#{@short}'"
    end
    @nets.push net
  end

  def flag? flag
    flag = flag.to_sym unless flag.kind_of? Symbol
    return @flags.include? flag
  end

  def flag_set flag
    flag = flag.to_sym unless flag.kind_of? Symbol
    @flags.add flag
  end

  def flag_clear flag
    flag = flag.to_sym unless flag.kind_of? Symbol
    @flags.reject! { |f| f == flag }
  end

  def problem? prob
    prob = prob.to_sym unless prob.kind_of? Symbol
    return @problems.include? prob
  end

  def problem_set prob
    prob = prob.to_sym unless prob.kind_of? Symbol
    @problems.add prob
  end

  def problem_clear prob
    prob = prob.to_sym unless prob.kind_of? Symbol
    @problems.reject! { |f| f == prob }
  end
end

class HostDB
  extend Forwardable
  def_delegators :@db, :each, :select, :reject, :reject!, :sort, :sort!

  def initialize
    @db = []
  end

  def add host
    raise ArgumentError.new "Requires a Host" unless host.kind_of? Host
    matchinghosts = @db.select { |h| h.short == host.short }
    unless matchinghosts.empty?
      raise ArgumentError.new "A Host with short hostname '#{host.short}' already exists"
    end
    if matchinghosts.size > 1
      raise ArgumentError.new "More than one Host with short hostname '#{host.short}' exists"
    end
    @db.push host
  end

  def hosts
    return @db
  end

  def shorts
    return @db.map { |h| h.short }
  end

  def byshort short
    raise ArgumentError.new "Short hostname must be a String (not a #{short.class})" unless short.kind_of? String
    matchinghosts = @db.select { |h| h.short == short }
    if matchinghosts.empty?
      newhost = Host.new(:short => short)
      @db.push newhost
      matchinghosts = [newhost]
    end
    return matchinghosts[0]
  end
end

###############################################################################
# Globals

# Command-line options
$opt = Hash.new

# Host database
$hostdb = HostDB.new

# This machine's IP information
$myip = Hash.new({})

###############################################################################
# Methods

def handle_options
  opt = Hash.new
  parser = OptionParser.new(1) do |p|
    p.program_name = $PROG_NAME
    p.version = $PROG_VERSION
    p.release = $PROG_RELEASE
    p.separator '---'
    p.summary_indent = '  '
    p.summary_width = 18
    p.banner = "Usage: #{$0} [<options>]"
    p.on('-d', '--debug', :NONE, 'Debug mode (extra output)') { |v| opt[:debug] = 1 }
  end
  begin
    parser.parse!
  rescue OptionParser::InvalidOption
    puts $!.message
    exit
  end
  return opt
end

def debug_puts str
  return unless $opt[:debug]
  puts "DEBUG: #{str}"
end

def wait_for_munin_update_lock
  # If there's a $MUNIN_UPDATE_LOCK in place, wait for it to go
  # away. It means Munin is updating right now, and we don't want to
  # run while that's happening.
  if File.exist? $MUNIN_UPDATE_LOCK
    debug_puts "Waiting for munin-update lockfile to clear ..."
    sleep 1
  end
  while File.exist? $MUNIN_UPDATE_LOCK
    sleep 1
  end
end

def where_are_we
  # Get all local (i.e. this machine) IP addresses and hostnames we
  # can find. Put them in $myip.

  # First get all network interfaces.
  ifs = `ip link show | sed -re '/^[[:space:]]*link/d;s/^[[:digit:]]+:[[:space:]]*([^:]+):.*\$/\\1/'`.split "\n"
  # For each interface, get all IP addresses.
  ifs.each do |intf|
    addrlines = `ip addr show #{intf} | grep -E '^[[:space:]]*inet[[:digit:]]*\\b'`.split "\n"
    next if addrlines.empty?
    addrlines.each do |addrline|
      pieces = addrline.strip.split /\s+/
      inetflag = false
      ip = nil
      pieces.each do |piece|
        if inetflag
          begin
            ipaddr, mask = piece.split '/'
            ip = IPAddr.new ipaddr
          rescue ArgumentError
            ip = nil
          end
          break
        else
          if piece =~ /^inet\d*$/
            inetflag = true
          end
        end
      end
      unless ip.nil?
        $NETINFO.each do |netlabel, netinfo|
          netinfo['ipranges'].each do |iprange|
            if iprange.include? ip
              $myip[netlabel] = Hash.new unless $myip.key? netlabel
              $myip[netlabel]['ips'] = [] unless $myip[netlabel].key? 'ips'
              $myip[netlabel]['ips'].push ip
              $myip[netlabel]['interface'] = intf
            end
          end
        end
      end
    end
  end
#  if $opt[:debug]
#    $myip.each do |netlabel, ipdata|
#      puts "#{netlabel}:"
#      puts "  interface: #{ipdata['interface']}"
#      ips = ipdata['ips']
#      puts "  ips: #{ips.map { |ip| "#{ip.to_s} (#{if ip.ipv4? then 'ipv4' elsif ip.ipv6? then 'ipv6' end})" }.join ', '}"
#    end
#  end
end

def read_ghc_config
  debug_puts "Reading #{$GHC_CONFIG}"
  $ghc_config = YAML.load(File.read $GHC_CONFIG)
end

def read_munin_config
  debug_puts "Reading #{$MUNIN_CONFIG}"
  $munin_config = YAML.load(File.read $MUNIN_CONFIG)
end

def init
  $opt = handle_options
  where_are_we
  read_ghc_config
  wait_for_munin_update_lock
  read_munin_config
end

def match_re_array test, res_r
  # Given a string and an array of regular expressions, return true if
  # the string matches any of the regexes, and false if it doesn't
  # match any of them.
  #
  # The first argument can also be an array of strings. In this case,
  # return true if any of the strings in the array matches any of the
  # regexes, and false if none of the strings matches any of the
  # regexes.
  res_r.each do |res|
    if res.kind_of? Regexp
      re = res
    else
      re = Regexp.new res
    end
    if test.kind_of? Array
      test.each do |t|
        if re.match t
          return true
        end
      end
    else
      return true if re.match test
    end
  end
  return false
end

def make_ldap_query filter
  # Make an LDAP query using a DNS SRV query to get the LDAP
  # servers. Returns an array of LDAP entry objects. Uses the global
  # $LDAP_DOMAIN for the DNS search and global $LDAP_BASE for the LDAP
  # query.

  # First find the LDAP server(s).
  ldap_servers = []
  Resolv::DNS.open do |dns|
    ress = dns.getresources "_ldap._tcp.#{$LDAP_DOMAIN}.", Resolv::DNS::Resource::IN::SRV
    ress.reject! { |r| !r.kind_of? Resolv::DNS::Resource::IN::SRV }
    if ress.empty?
      raise RuntimeError.new "No LDAP servers found"
    end
    ress.sort! { |r1, r2| r1.priority <=> r2.priority }
    ldap_servers = ress.map { |r| {'host' => r.target.to_s, 'port' => r.port} }
  end

  # Make an LDAP query.
  ldap = nil
  bound = false
  ldap_servers.each do |server|
    ldap = Net::LDAP.new(
                         :host => server['host'],
                         :port => server['port'],
                         :base => $LDAP_BASE
                         )
    if ldap.bind
      bound = true
      break
    else
      next
    end
  end
  unless bound
    raise RuntimeError.new "Unable to bind to an LDAP server"
  end
  entries = []
  ldap.search(:filter => filter) do |entry|
    entries.push entry
  end
  return entries
end

def populate_hostdb
  # Gets host data from the LDAP server, the public DNS server, and
  # the local host to populate $hostdb.
  #
  # Assumptions we make:
  #
  # 1. Any public hostnames a host has will be reflected by private
  # hostnames (e.g. catcher.uits.indiana.edu/siab.grid.iu.edu will
  # have private hostnames catcher.goc and siab.goc). The reverse is
  # not necessarily so, however, and we don't assume it. Put another
  # way, the list of private hostnames will be complete but may be
  # larger than the list of public hostnames.

  # We are not going to go through every IP address in the IP
  # ranges. This becomes prohibitively resource-intensive with
  # IPv6. Instead, we'll use the convenient fact that we have an LDAP
  # server that has entries for every defined host. This LDAP
  # directory is populated from the same source data from which the
  # private DNS is populated, so it should give us all the hosts we
  # need to look at.
  debug_puts "Querying LDAP database"
  entries_r = make_ldap_query('objectClass=ipHost')
  entries_r.each do |entry|
    # Obtain the primary private hostname.
    priv_main = (entry.dn.split ',')[0].sub /^cn=/, ''
    # Obtain the short hostname.
    short = (priv_main.split '.')[0]
    # Skip if it begins with 'unused-'.
    next if priv_main.start_with? 'unused-'
    # Get the Host object. This will create it if it doesn't already
    # exist.
    host = $hostdb.byshort short
    privnet = host.net 'private'
    privnet.main = priv_main
    # Skip it if the config file says to ignore it (i.e. if it's found
    # in $ghc_config['ignore']['fqdn'] or ...['short']).
    if match_re_array privnet.main, $ghc_config['ignore']['fqdn'] \
      or match_re_array short, $ghc_config['ignore']['short']
      host.flag_set :ignore
      next
    end
    # Obtain all other hostnames the host may have other than
    # priv_main.
    privnet.alts = entry.cn.map { |e| e.to_s }.reject { |cn| cn == priv_main }
    # Skip this host if the config file says to ignore any of the
    # priv_alts.
    if match_re_array privnet.alts, $ghc_config['ignore']['fqdn']
      host.flag_set :ignore
      next
    end
    # Obtain all this host's IP addresses.
    privnet.ips = entry.ipHostNumber.map { |ip| IPAddr.new ip.to_s }
  end

  # Now query the public DNS server for any public hostnames that may
  # result from attaching the public domains to the short names. Note
  # that some of these may not be in our IP ranges due to naming
  # coincidences, so check for that and ignore those.
  debug_puts "Querying DNS server"
  Resolv::DNS.open do |res|
    $hostdb.each do |host|
      # If this host is already marked to ignore, there's no point
      # gathering more data about it.
      next if host.flag? :ignore
      pubnet = host.net 'public'
      # Shorten every private hostname to test it.
      (host.net('private').main.to_a + host.net('private').alts).each do |hostname|
        hostname_short = (hostname.split '.')[0]
        # If this shortened hostname matches the ignore list, skip it.
        if match_re_array hostname_short, $ghc_config['ignore']['short']
          host.flag_set :ignore
          next
        end
        # Add each public domain suffix to this shortened hostname to
        # test it.
        $NETINFO['public']['domains'].each do |suffix|
          pub_fqdn = "#{hostname_short}.#{suffix}"
          # If this new FQDN matches the ignore list, skip it.
          if match_re_array pub_fqdn, $ghc_config['ignore']['fqdn']
            host.flag_set :ignore
            next
          end
          # See if there are any CNAMEs matching pub_hostname.
          answers = res.getresources pub_fqdn, Resolv::DNS::Resource::IN::CNAME
          if answers.size > 0
            answers.each do |answer|
              alt = answer.name.to_s
              if match_re_array alt, $ghc_config['ignore']['fqdn']
                host.flag_set :ignore
                next
              end
              pubnet.push_alt pub_fqdn
              pubnet.push_alt alt
            end
            # If we found a hostname as a CNAME, don't go on to
            # searching for it as an A or AAAA record.
            next
          end
          # See if there are any A or AAAA records matching pub_hostname.
          [Resolv::DNS::Resource::IN::A, Resolv::DNS::Resource::IN::AAAA].each do |rectype|
            answers = res.getresources pub_fqdn, rectype
            answers.each do |answer|
              # Ignore them if they're in the list.
              if match_re_array pub_fqdn, $ghc_config['ignore']['fqdn']
                host.flag_set :ignore
                next
              end
              ipaddr = IPAddr.new answer.address.to_s
              # If the IP address isn't in any of the IP ranges for
              # this network, skip it (for example, there is a
              # monitor.uits.indiana.edu that isn't one of ours)
              in_network = false
              $NETINFO['public']['ipranges'].each do |ipr|
                if ipr.include? ipaddr
                  in_network = true
                  break
                end
              end
              next unless in_network
              pubnet.main = pub_fqdn
              pubnet.push_ip ipaddr
            end
          end
        end
      end
      pubnet.alts.reject! { |hostname| hostname == pubnet.main }
    end
  end

  # Uniquify the arrays.
  debug_puts "Uniquifying"
  $hostdb.each do |host|
    $NETINFO.keys.each do |netlabel|
      next unless host.net? netlabel
      hnet = host.net netlabel
      begin
        hnet.alts.uniq!
      rescue
        puts "#{short}: #{netlabel}"
        puts YAML.dump host
        abort
      end
      hnet.ips.uniq!
    end
  end

  # Add configuration flags (other than ignore, which we've already
  # dealt with) to any hosts that match.
  debug_puts "Adding configuration flags"
  $hostdb.each do |host|
    %w(public_only_ok private_only_ok noping nomunin).each do |flag|
      next unless $ghc_config.key? flag
      next unless $ghc_config[flag].key? 'short'
      next if $ghc_config[flag]['short'].nil?
      if match_re_array host.short, $ghc_config[flag]['short']
        host.flag_set flag.to_sym
      end
    end
    host.nets.each do |net|
      %w(public_only_ok private_only_ok noping nomunin).each do |flag|
        next unless $ghc_config.key? flag
        next unless $ghc_config[flag].key? 'fqdn'
        next if $ghc_config[flag]['fqdn'].nil?
        if match_re_array net.main, $ghc_config[flag]['fqdn'] \
          or match_re_array net.alts, $ghc_config[flag]['fqdn']
          host.flag_set flag.to_sym
        end
      end
    end
  end

  # Deal with the data in $myip.
  debug_puts "Adding localhost data"
  $NETINFO.keys.each do |netlabel|
    next unless $myip.key? netlabel
    inet = $myip[netlabel]
    found = false
    $hostdb.each do |host|
      next unless host.net? netlabel
      hnet = host.net netlabel
      unless (hnet.ips.map { |ip| ip.to_s } & inet['ips'].map { |ip| ip.to_s }).empty?
        lnet = host.net 'loopback'
        lnet.main = 'localhost'
        lnet.alts = ['localhost.localdomain']
        lnet.ips = [(IPAddr.new '127.0.0.1'), (IPAddr.new '::1')]
        found = true
        break
      end
      break if found
    end
    break if found
  end

  # Summarize collected data if -d flag is set.
  if $opt[:debug]
    $hostdb.sort { |h1, h2| h1.short <=> h2.short }.each do |host|
      puts "#{host.short}: #{host.flags.map { |f| f.to_s }.join ' '}"
      ['loopback', 'private', 'public'].each do |netlabel|
        next unless host.net? netlabel
        puts "  #{netlabel}: #{(host.net netlabel).main}"
        puts "    alts: #{(host.net netlabel).alts.join ', '}"
        puts "    ips: #{(host.net netlabel).ips.join ', '}"
      end
    end
  end

  # Get rid of ignored hosts.
  debug_puts "Removing ignored hosts"
  $hostdb.reject! { |host| host.flag? :ignore }
end

def compare
  # Go through $hostdb and search for potential trouble spots. These
  # could be:
  #
  # * Hosts that are defined in public DNS but not private DNS (unless
  # they're set 'public_only_ok' in $GHC_CONFIG)
  #
  # * Hosts that are defined in private DNS but not public DNS (unless
  # they're set 'private_only_ok' in $GHC_CONFIG)
  #
  # * Hosts that are defined in LDAP/DNS but don't respond to ping
  # (unless they're set 'noping' in $GHC_CONFIG)
  #
  # * Hosts that are defined in LDAP/DNS but aren't monitored by Munin
  # (unless they're set 'nomunin' in $GHC_CONFIG)
  #
  # * Hosts that aren't defined in LDAP/DNS, but Munin is attempting
  # to monitor them

  problems = 0
  # Looking for hosts that are defined in LDAP (or they wouldn't be in
  # $hostdb) but undefined in either public DNS or private DNS, or
  # both (which would be really weird).
  debug_puts "Looking for problems ..."
  $hostdb.each do |host|
    privnet = host.net 'private'
    pubnet = host.net 'public'
    # If it's defined in both networks ...
    if !privnet.main.empty? and !pubnet.main.empty?
    elsif privnet.main.empty?
      # The host is in public DNS but not private DNS.
      host.problem_set :public_only
      problems += 1
    elsif pubnet.main.empty?
      # The host is in private DNS but not public DNS.
      host.problem_set :private_only
      problems += 1
    else
      # The host is not in any DNS, which is quite strange.
      host.problem_set :nodns
      problems += 1
    end

    # Now let's ping.
    unless host.flag? :noping
      %w(private public).each do |netlabel|
        net = host.net netlabel
        unless net.main.empty?
          net.thread = Thread.new { net.ping }
        end
      end
    end

    unless host.flag? :nomunin
      # See if the host is monitored by Munin by looking in
      # $munin_config. The problem is that sometimes in Munin's
      # configuration a host will be known by a different name, like
      # one of its CNAME aliases.
      unless privnet.main.empty?
        muninname = nil
        if $munin_config['nodes'].key? host.short
          muninname = host.short
        else
          privnet.alts.each do |alt|
            shortalt = (alt.split '.')[0]
            if $munin_config['nodes'].key? shortalt
              muninname = shortalt
              break
            end
          end
        end
        if muninname
          # Remember the host's "Munin name".
          host.muninname = muninname
          # Likewise, link the Munin config record back to the host DB
          # by remembering what it is "known as" there.
          $munin_config['nodes'][muninname]['knownas'] = host.short
        else
          host.problem_set :nomunin
          problems += 1
        end
      end
    end
  end

  # Join up the ping threads.
  $hostdb.each do |host|
    %w(private public).each do |netlabel|
      net = host.net netlabel
      unless net.thread.nil?
        net.thread.join
        net.thread = nil
        unless net.pinged_ok?
          host.problem_set "#{netlabel}_noping".to_sym
          problems += 1
        end
      end
    end
  end

  # Look for monitored hosts that don't exist.
  $munin_config['nodes'].each do |short, mconfig|
    # If there is a Munin node that wasn't given a "knownas" name
    # earlier, it's exactly what we're looking for in this step.
    unless mconfig.key? 'knownas'
      mconfig['nonexistent'] = true
      problems += 1
    end
  end

  $hostdb.sort { |a, b| a.short <=> b.short }.each do |host|
    if host.problems.size > 0
      puts "*** #{host.short}:"
      if host.problems.include? :public_only
        puts "  * Defined in public DNS but not in private DNS"
      end
      if host.problems.include? :private_only
        puts "  * Defined in private DNS but not in public DNS"
      end
      if host.problems.include? :nodns
        puts "  * Not defined in DNS at all"
      end
      if host.problems.include? :public_noping \
        and host.problems.include? :private_noping \
        and host.problems.include? :nomunin
        puts "  * Not responding to any pings and not monitored -- new or retired host?"
      elsif host.problems.include? :public_noping \
        and host.problems.include? :private_noping
        puts "  * Not responding to pings on public or private network (but monitored)"
      elsif host.problems.include? :private_noping
        puts "  * Not responding to pings on private network (but monitored)"
      elsif host.problems.include? :public_noping
        puts "  * Not responding to pings on public network (but monitored)"
      elsif host.problems.include? :nomunin
        puts "  * Not monitored by Munin"
      end
    end
  end
  return problems
end

###############################################################################
# Main

init
populate_hostdb
compare
