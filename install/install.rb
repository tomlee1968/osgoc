#!/usr/bin/env ruby

# Ansible-based master installation script for GOC services
#
# The goal here is a centralized, uniform installation system for instances of
# services. The directory this script is in should have 'ansible' and
# 'scripted' subdirectories. The 'ansible' directory contains
# * Ansible inventory for production, testing, development
# * Playbooks for each service
# * A roles directory with a subdirectory for each service
# * Ansible configuration file

# The 'scripted' subdirectory contains the traditional install tree with one
# subdirectory for each service, plus one called 'common' that will contain
# files applicable to all services.
#
# ./scripted/
#  +-- common/
#  +-- install
#  +-- myosg/
#  L-- oim/
#
# These subdirectories should each have a script called 'install' that this
# script will source (including 'common', and that is where instructions should
# go that involve files or scripts in 'common', for the purpose of
# compartmentalization -- do one thing, and do it well). Those service install
# scripts can do whatever is necessary for the installation of the service, but
# they should handle the next iteration ...
#
# ./scripted/
#  +-+ common/
#  | +-- install
#  | +-- install_networking
#  | L-- install_openssh
#  +-- install
#  +-- myosg/
#  L-- oim/
#
# Each of those subdirectories should have one subdirectory for each instance
# (including one called 'common' containing files applicable to every
# instance). It is possible for those subdirectories (including 'common') to
# contain a further 'install' script, which will be sourced if it exists, but
# if it doesn't exist, nothing will happen.
#
# ./scripted/
#  +-- common/
#  +-- install
#  +-- myosg/
#  L-+ oim/
#    +-+ common/
#      +-- oim.conf
#      L-- otherconfig.conf
#    +-- install
#    +-- oim-itb/
#    +-- oim1/
#    L-- oim2/
#
# The service subdirectory MUST be the same as the service's name in
# DNS/Puppet/etc.; i.e. it must be a substring of the instance name(s). The
# instance subdirectory must be the same as the instance's name in
# DNS/Puppet/etc.; i.e. it must be the same as the DNS short hostname and the
# VM's basename. If it isn't, the system will be broken. If there is a
# compelling reason to make this more flexible, it can be considered, but years
# of experience has indicated that having the service subdirectory named
# differently from the service leads only to confusion and adds no utility.

# Please note that instance names can be short hostnames -- please don't use
# redirector1.grid.iu.edu when you could just use redirector1.

require 'ipaddr'
require 'open3'
require 'optparse'
require 'resolv'
require 'yaml'

###############################################################################
# Settings
###############################################################################

# A prefix for the pfputs method, to tell people what script these messages are
# coming from, as opposed to messages from other scripts or commands called by
# this script.
$pfx = 'install'

# The path to the Ansible-Vault password. This is a shared secret used to
# encrypt sensitive data such as keys and passphrases so such data doesn't get
# stored in plaintext on the version control server. This password must exist
# on the control machine, at least while you're running Ansible rules on it,
# but you won't need it on any managed node. We don't want plaintext or
# easily-decryptable sensitive data lying around where people can see it, even
# "temporarily" (we all know that it's far too easy for "temporarily" to turn
# into "permanently", and no amount of secure deletion is as secure as never
# putting the data there in the first place)! Be very careful about sharing
# this password.
$vault_pw_file = "#{ENV['HOME']}/.ansible/vault_pw.txt"

###############################################################################
# Setup
###############################################################################

$DIR = File.expand_path(File.dirname $0)

###############################################################################
# Methods
###############################################################################

def pfputs(string)
  # Just a puts, but with $pfx prepended to the string.
  puts "#{$pfx}>>> #{string}"
end

def debug_puts(string)
  # Does a puts, with a DEBUG prefix, but only if $opt[:debug] is set.
  puts "DEBUG>>> #{string}" if $opt.key? :debug
end

def parse_options
  # Parse the command-line options, setting keys in $opt based on what they
  # are.

  $opt = Hash.new

  parser = OptionParser.new(1) do |p|
    p.program_name = 'install'
    p.version = 'v0.1'
    p.release = 'alpha'
    p.separator '---'
    p.summary_indent = '  '
    p.summary_width = 18
    p.banner = "Usage: #{$0} [<options>] <targethost>"
    p.on('-d', '--debug', :NONE, 'Debug mode (extra output)') { |v| $opt[:debug] = 1 }
    p.on('-i', '--instance', :REQUIRED, 'Instance of service to install') { |v| $opt[:instance] = v }
    p.on('-t', '--test', :NONE, 'Toggles test mode (show commands to run but do nothing)') { |v| $opt[:test] = 1 }
    p.on('', '--vmhost', :REQUIRED, 'Sets VM host to use, overriding default') { |v| $opt[:vmhost] = v }
    p.on('', '--vmversion', :REQUIRED, 'Sets VM version to use; default 1') do |v|
      if !v.nil? and !v.empty? and v.to_i > 0
        $opt[:vmversion] = v
      else
        pfputs "Bad --vmversion"
        exit
      end
    end
  end

  begin
    parser.parse!
  rescue OptionParser::InvalidOption
    pfputs $!.message
  end
  hostname = ARGV[0]
  unless hostname
    puts parser.help
    exit 1
  end
  return hostname
end

def get_short_host(hostname)
  # Just converts the hostname into a short hostname.
  return hostname.sub /\..*$/, ''
end

# Just extends RuntimeError in case we want to rescue a DNSError.
class DNSError < RuntimeError
end
class InventoryError < RuntimeError
end

def ensure_shorthost_exists(shorthost)
  # Query DNS to make sure that the global and local hostnames exist in some
  # form. This means that shorthost.grid.iu.edu or shorthost.uits.indiana.edu
  # must exist, and so must shorthost.goc. It must exist in both places, and if
  # it doesn't, print an error and exit.

  def as_for_hostnames(resolver, hostnames)
    records = Array.new
    [Resolv::DNS::Resource::IN::A, Resolv::DNS::Resource::IN::AAAA].each do |rtype|
      hostnames.each do |h|
        results = resolver.getresources h, rtype
        records += results
      end
    end
    return records
  end

  globals = ['grid.iu.edu', 'uits.indiana.edu'].map { |x| "#{shorthost}.#{x}" }
  locals = ["#{shorthost}.goc"]
  global_as = Array.new
  local_as = Array.new
  Resolv::DNS.open do |resolver|
    global_as += as_for_hostnames(resolver, globals)
    local_as += as_for_hostnames(resolver, locals)
  end
  
  if global_as.length + local_as.length == 0
    raise DNSError.new("Unable to find any of these addresses in DNS: #{globals.concat(locals).join(', ')} -- make sure you've typed the hostname correctly, and if you have, contact your system administrator and/or DNS admin.")
  elsif global_as.length == 0
    raise DNSError.new("Unable to find #{globals.join(', ')} in DNS -- make sure you've typed the hostname correctly, and if you have, contact your system administrator and/or DNS admin.")
  elsif local_as.length == 0
    raise DNSError.new("Unable to find #{locals.join(', ')} in DNS -- make sure you've typed the hostname correctly, and if you have, contact your system administrator.")
  end
end

def is_vm_according_to_dns?(shorthost)
  # Tom set up a system whereby we can tell whether a host is a VM based on its
  # LAN IP address. We use the IPv4 range 192.168.96.0/22, but IPv4 addresses
  # in 192.168.97.0/24 are VMs. Likewise, we use the IPv6 range
  # fd2f:6feb:37:1::/48, but addresses in fd2f:6feb:37:1::/64 are VMs. This
  # method appends '.goc' to the shorthost, looks up A and AAAA records in DNS,
  # and returns true if the host is in the VM range, false otherwise. Raises an
  # exception if the A and AAAA records don't agree (someone's made a mistake
  # in assigning the addresses in the LAN DNS server). Also raises an exception
  # if there are no DNS query results at all; that would be very odd,
  # especially considering we checked earlier to make sure there were both
  # global and local DNS entries for the host. It's OK for there to only be
  # IPv4 or IPv6 records, but none at all can't be allowed.
  hostname = "#{shorthost}.goc"
  answer = nil
  checked_addrs = Array.new
  Resolv::DNS.open do |resolver|
    ipv4_results = resolver.getresources hostname, Resolv::DNS::Resource::IN::A
    ipv4_range = IPAddr.new('192.168.97.0/24')
    ipv4_results.each do |r|
      addr = IPAddr.new r.address.to_s
      checked_addrs.push addr
      inrange = ipv4_range.include? addr
      if !answer.nil? and inrange != answer
        raise DNSError.new("Some LAN IP addresses claim this is a VM while others claim it isn't (#{checked_addrs.join(', ')}) -- someone has set up the LAN IP addresses improperly! Contact your system administrator.")
      end
      answer = inrange
    end
    ipv6_results = resolver.getresources hostname, Resolv::DNS::Resource::IN::AAAA
    ipv6_range = IPAddr.new('fd2f:6feb:37:1::/64')
    ipv6_results.each do |r|
      addr = IPAddr.new r.address.to_s
      checked_addrs.push addr
      inrange = ipv6_range.include? addr
      if !answer.nil? and inrange != answer
        raise DNSError.new("Some LAN IP addresses claim this is a VM while others claim it isn't (#{checked_addrs.join(', ')}) -- someone has set up the LAN IP addresses improperly! Contact your system administrator.")
      end
      answer = inrange
    end
    if ipv4_results.length + ipv6_results.length == 0
      raise DNSError.new("Unable to find any A or AAAA records for #{hostname} in DNS -- make sure you've typed the hostname correctly, and if you have, contact your system administrator.")
    end
  end
  return answer
end

def gather_ansible_inv_data
  # Read all *.inv files in $DIR/ansible and return a data structure with their
  # data so we don't have to repeatedly read them.
  savedir = Dir.pwd
  Dir.chdir "#{$DIR}/ansible"
  sdata = Hash.new
  dh = Dir.open '.'
  dh.each do |file|
    next if file =~ /^\./
    next unless file =~ /\.inv$/
    svc = ''
    fh = File.open file, 'r'
    until fh.eof?
      # Get next line; remove trailing newline and leading/trailing whitespace.
      line = fh.gets.chomp.strip
      # Ignore blank lines.
      next if line == ''
      # Ignore comment lines.
      next if line.start_with? '#'
      # Look for [service] sections.
      if line =~ /^\[([^\]]+)\]$/
        match = $1
        svc = match
        # Make a subhash for that service unless it already exists or it
        # contains a colon like [service:vars], which we don't want to save.
        sdata[svc] = Hash.new unless sdata.key? svc or match =~ /:/
        next
      end
      # Ignore regular lines if they're not in a [section] or if they're in a
      # section with a colon like [service:vars].
      next if svc == '' or svc =~ /:/
      # Split off other whitespace-separated items. First one is the FQDN.
      line_items = line.split /\s+/
      fqdn = line_items[0]
      # Split off the first segment of the FQDN to be the short hostname.
      short = get_short_host fqdn
      # Save this instance under the service.
      if sdata[svc].key? short
        pfputs "ERROR: I've already seen the '#{short}' instance of '#{svc}' in '#{sdata[svc][short][:inv]}'! Now here it is in '#{file}' too!"
        pfputs "Cannot continue. Please fix."
        exit 1
      else
        sdata[svc][short] = Hash.new
        sdata[svc][short][:fqdn] = fqdn
        sdata[svc][short][:inv] = file
      end
    end
    fh.close
  end
  Dir.chdir savedir
  return sdata
end

def gather_ansible_services(sdata)
  # Return a list of all services supported by Ansible. This will just be an
  # array of strings. The services found by gather_ansible_inv_data must also
  # have a <service>.yaml playbook and a roles/<service> directory in the
  # Ansible directory, or they're not considered supported.
  savedir = Dir.pwd
  Dir.chdir "#{$DIR}/ansible"
  services = Array.new
  sdata.keys.each do |svc|
    next unless File.exist? "#{svc}.yaml"
    next unless File.directory? "roles/#{svc}"
    services.push svc
  end
  Dir.chdir savedir
  return services
end

def gather_vm_data
  # Collect data about VMs: where they are and where we think they should
  # be. There will be a hash whose keys are the short hostnames of service
  # instances, with values that are hashes. Those hashes have keys
  # :inthost, where the value is just the short hostname of the VM host
  # where Ansible's rules think the instance should exist, and :occur,
  # whose value is an array of hashes, one for each time that instance does in
  # fact appear on a VM host. Those hashes have keys :version (the VM version
  # number), :state (whether the VM is up or down), and :host (the VM host).
  #
  # data['foo-itb'] = {
  #  :inthost => 'devfoovm01',
  #  :occur => [
  #    {
  #      :host => 'devfoovm01',
  #      :version => '1',
  #      :state => :down,
  #    },
  #    {
  #      :host => 'devfoovm01',
  #      :version => '2',
  #      :state => :up,
  #    }

  pfputs "Gathering VM information ..."
  # First find the list of VM hosts. They are listed in the [kvmhost] group in
  # ansible/itb.inv and ansible/production.inv.
  savedir = Dir.pwd
  Dir.chdir "#{$DIR}/ansible"
  vmhosts = Array.new
  %w(itb production).each do |maturity|
    IO.popen("ansible-playbook -i #{maturity}.inv --list-hosts kvmhost.yaml", 'r') do |pipe|
      until pipe.eof?
        line = pipe.gets.chomp
        line.gsub! /^\s+/, ''
        next if line.empty?
        next if line =~ /:/
        vmhosts.push line
      end
    end
  end
  # Now look in the Ansible files to see where each VM should be.
  intendedhost = Hash.new
  dh = Dir.open("host_vars")
  dh.each do |file|
    next if file =~ /^\./
    fh = File.open "host_vars/#{file}", 'r'
    until fh.eof?
      line = fh.gets.chomp
      if line =~ /^\s*vmhost:\s/
        line.sub! /^\s+/, ''
        (unused, vmhost) = line.split /\s+/, 2
        intendedhost[file.sub(/\..*$/, '')] = vmhost
        break
      end
    end
    fh.close
  end
  dh.close
  Dir.chdir savedir
  # Now ask each VM host about its VMs.
  vms = Array.new
  threads = vmhosts.map do |vmhost|
    Thread.new do
#      debug_puts "#{vmhost}: begin"
      vmshorthost = get_short_host vmhost
      Open3.popen3("ssh #{vmshorthost} lsvm") do |stdin, stdout, stderr, thread|
        until stdout.eof?
          line = stdout.gets.chomp
          next if line =~ /^-/
          next if line =~ /^VM/
          (vmnameplusvers, vmstate) = line.split /\s+/
          (vmname, vmversion) = vmnameplusvers.split /\./
          vmhash = { \
                     :name => vmname, \
                     :version => vmversion, \
                     :state => vmstate.to_sym, \
                     :host => vmshorthost, \
                   }
          vms.push vmhash
        end
      end
#      debug_puts "#{vmhost}: end"
    end
  end
  threads.each { |t| t.join }
  # Now we put together a data hash.
  data = Hash.new
  intendedhost.each do |name, host|
    data[name] = Hash.new unless data.key? name
    data[name][:inthost] = host
  end
  vms.each do |vm|
    data[vm[:name]] = Hash.new unless data.key? vm[:name]
    occurrence = { \
                 :version => vm[:version], \
                 :state => vm[:state], \
                 :host => vm[:host], \
               }
    data[vm[:name]][:occur] = Array.new unless data[vm[:name]].key? :occur
    data[vm[:name]][:occur].push occurrence
  end
  # Return that data hash.
  return data
end

def find_vm_irregularities(instance, data)
  # Given an instance and the data hash generated by gather_vm_data, see if
  # there are any irregularities with that instance's occurrences -- are there
  # more than one of them online at the same time? Are there any apperances of
  # that instance on unintended hosts? Tell the user and exit for now, so they
  # can fix it and rerun.

  unless data.key? instance
    puts "ERROR: No instance data for #{instance}!"
    puts "This is very strange. Cannot continue."
    exit 1
  end
  mydata = data[instance]
  # In case where there are no occurrences of the VM (as with a new service
  # where there are no VMs yet), data[instance] will exist but
  # data[instance][:occur] will be nil.
  mydata[:occur] = Array.new unless mydata.key? :occur
  # Print the current state of affairs.
  vbs = Hash.new
  [:up, :down].each do |state|
    vbs[state] = mydata[:occur].select { |a| a[:state] == state }
    vbs[state].sort! { |a, b| a[:version].to_i <=> b[:version].to_i }
    vbs[state].sort! { |a, b| a[:host] <=> b[:host] }
  end

  puts
  [:up, :down].each do |state|
    adjective = 'Offline'
    adjective = 'Online' if state == :up
    if vbs[state].length > 0
      pfputs "#{adjective} '#{instance}' VMs:"
      vbs[state].each { |a| pfputs "  #{a[:host]}: #{instance}.#{a[:version]}" }
    else
      pfputs "#{adjective} '#{instance}' VMs: *** None ***"
    end
  end
  

  # First of all, is there more than one occurrence online right now? If so,
  # complain and exit immediately; that's very bad and needs to be fixed now.
  if vbs[:up].length > 1
    pfputs "ERROR: There is more than one #{instance} online right now!"
    pfputs "Cannot continue. Please fix this. Exiting."
    exit 1
  end

  # If there is an online VM, assume the user means to run this on that
  # VM. Reasoning: If they meant to create a new VM, they would have shut down
  # the existing one, and they still can, if they quit this script, go do it,
  # and run this script again. This script should not be in the business of
  # automatically shutting down existing VMs. I'm trying to write the script to
  # do a lot for people, but I have to draw the line somewhere, it seems good
  # to draw the line between "things that could bring down an existing service
  # and should be done deliberately by a person" and "things that won't hurt
  # anything."
  if vbs[:up].length == 1
    upvm = vbs[:up][0]
    # Is that VM where we think it's supposed to be? If not, warn the user.
    if upvm[:host] != mydata[:inthost]
      pfputs "Just FYI, '#{instance}' is up on #{upvm[:host]},"
      pfputs "but we think it is supposed to be on #{mydata[:inthost]}."
      pfputs "You may want to move that VM, or change its vmhost in ansible/host_vars."
    end
    # If the user is trying to create a new VM with an old VM already running,
    # this script is likely to either not work (at best) or break the running
    # VM (at worst). Warn the user and don't proceed in these cases. First, the
    # case where they specify a new version number:
    if $opt.key? :vmversion and $opt[:vmversion] != upvm[:version]
      pfputs "You specified '--vmversion #{$opt[:vmversion]}',"
      pfputs "but the sole online '#{instance}' is #{instance}.#{upvm[:version]}, on '#{upvm[:host]}'."
      pfputs "This suggests you want to create '#{instance}.#{$opt[:vmversion]}',"
      pfputs "which will either refuse to come online or break the existing VM."
      pfputs "To proceed, you must either:"
      pfputs "  * Shut down '#{instance}.#{upvm[:version]} (to create a new VM), or"
      pfputs "  * Not specify --vmversion (to run on the existing VM)."
      pfputs "Cannot proceed; exiting."
      exit 1
    end
    # Then there's the case where they specify a different host, no matter the
    # version number.
    if $opt.key? :vmhost and $opt[:vmhost] != upvm[:host]
      pfputs "You specified '--vmhost #{$opt[:vmhost]}',"
      pfputs "but the sole online '#{instance}' is #{instance}.#{upvm[:version]}, on '#{upvm[:host]}'."
      pfputs "This suggests you want to create a new VM on '#{$opt[:vmhost]}',"
      pfputs "which will either refuse to come online or break the existing VM."
      pfputs "To proceed, you must either:"
      pfputs "  * Shut down '#{instance}.#{upvm[:version]} (to create a new VM), or"
      pfputs "  * Not specify --vmhost (to run on the existing VM)."
      pfputs "Cannot proceed; exiting."
      exit 1
    end
    # No matter whether it's supposed to be there or not, we're going to have
    # Ansible look for the VM where the online one is, unless the user
    # specified a different --vmhost (and if that was the case, we would have
    # exited already).
    $opt[:vmhost] = upvm[:host] unless $opt.key? :vmhost
    # Not that it will be used, but get the version.
    $opt[:vmversion] = upvm[:version] unless $opt.key? :vmversion
  else
    # There are no online VMs. Are there offline ones?
    if vbs[:down].length > 0
      # There are no online VMs, but there's at least one offline VM. What
      # host(s) is/are it/they on? Are any of them not on the intended host for
      # this VM?
      unintended = vbs[:down].select { |a| a[:host] != mydata[:inthost] }
      if unintended.length > 0
        pfputs "According to the files in ansible/host_vars,"
        pfputs "'#{instance}' is supposed to be on '#{mydata[:inthost]}'."
        pfputs "However, although there are no online occurrences of '#{instance}',"
        unintended.each do |a|
          pfputs "* '#{instance}.#{a[:version]}' is on '#{a[:host]}'"
        end
      end
      # Unless the user specified a --vmhost, use the intended host.
      $opt[:vmhost] = mydata[:inthost] unless $opt.key? :vmhost
      # Unless the user specified a --vmversion, find the highest existing
      # offline version and use that plus one.
      maxversion = (vbs[:down].max_by { |a| a[:version].to_i })[:version].to_i
      $opt[:vmversion] = (maxversion + 1).to_s unless $opt.key? :vmversion
    else
      # There are no online or offline VMs. We're going to create instance.1 on
      # mydata[:inthost], unless the user specified a different VM
      # version with --vmversion or a different VM host with --vmhost.
      $opt[:vmhost] = mydata[:inthost] unless $opt.key? :vmhost
      $opt[:vmversion] = '1' unless $opt.key? :vmversion
    end
  end
  # Print what we're going to do and ask the user if it's OK.
  puts
  if vbs[:up].length > 0
    pfputs "We will be running the install script on the running instance of #{instance},"
    pfputs "which is '#{instance}.#{upvm[:version]}' on VM host '#{$opt[:vmhost]}'."
  else
    pfputs "We will be creating '#{instance}.#{$opt[:vmversion]}' on VM host '#{$opt[:vmhost]}'."
  end
  answer = ask_user 'Is this OK? (Y/n)?', %w(y n), 'y', 'OK, we need a yes or no here.'
  if answer == 'n'
    pfputs 'Exiting by user request.'
    exit 0
  end
end

def print_known_columns(strings, cols, width)
  # Print an array in the given number of columns with spacing as even as
  # possible in the given width.
  cols = 1 unless defined? cols
  rows = (strings.length + cols - 1) / cols
  #  puts "#{strings.length} items: #{cols} columns means #{rows} rows"
  row_width = 0
  col_widths = Array.new
  (0...cols).each do |col|
    colfirst = col*rows
    break if colfirst > strings.length - 1
    collast = [colfirst + rows, strings.length].min - 1
    col_width = strings[colfirst..collast].max { |a, b| a.length <=> b.length }.length
    col_widths.push(col_width)
    row_width += col_width
  end
  (0...rows).each do |row|
    col = 0
    row_strings = Array.new
    while true
      i = col*rows + row
      break if i > strings.length - 1
      row_strings.push "%-#{col_widths[col]}s" % strings[i]
#      puts "column #{col}, row #{row} -> #{i}"
      col += 1
    end
    sep = ' '*((width - row_width)/cols)
    pfputs row_strings.join sep
  end
end

def optimal_rows(strings, width, gap)
  # Given an array of strings, a line width to fit them in, and a minimal gap
  # between columns, figure out the optimal number of rows to print the strings
  # in.
  #
  # We're talking about printing in down-the-column order -- that is,
  # 1 3 5 7
  # 2 4 6 etc.
  #
  # Columns should be aligned -- that is, each column should be given an amount
  # of space equal to the length of the longest string in the column. This
  # complicates things greatly. We'll have to consider proposed numbers of rows
  # and figure out the width of the entire assemblage, seeing whether it then
  # fits within the line.
  #
  # Start with rows equal to the number of items and decrease, in case the
  # width is really small.
  
  n = strings.length
  # Set optrows to n and replace its value when we find something better.
  optrows = n
  n.downto(1) do |rows|
    # The number of columns necessary to print all n items.
    cols = (n + rows - 1)/rows
    # Calculate the row width for this number of rows.
    row_width = 0
    (0...cols).each do |col|
      # Calculate the index within strings[] of the first and last items in the
      # column.
      colstart = col*rows
      colend = [colstart + rows, n].min - 1
      # Find the longest string in the column.
      col_width = strings[colstart..colend].max { |a, b| a.length <=> b.length }.length
      # Add the length of that longest string, plus gap, to the total row width.
      row_width += col_width + gap
    end
    # We don't need the gap at the end.
    row_width -= gap
    # If row_width exceeds width, we can't use this number of rows -- or any
    # lower number.
    break if row_width > width
    # We found something better.
    optrows = rows
  end
  return optrows
end

def print_columns(strings)
  # Print an array in columns, utilizing the screen width to its utmost.
  (screen_rows, screen_columns) = `stty size`.split(/\s+/).map { |str| str.to_i }
  rows = optimal_rows(strings, screen_columns, 2)
  cols = (strings.length + rows - 1) / rows
  print_known_columns(strings, cols, screen_columns)
end

def choose_from_array(strings)
  # Ask the user to choose a number from a printed array of strings.
  strings.sort!
  strings_lines = Array.new
  strings.each_index { |i| strings_lines.push "#{i + 1}. #{strings[i]}" }
  answer = nil
  while answer.nil? or answer.empty? or answer.to_i < 1 or answer.to_i > strings.length
    print_columns strings_lines
    print "Select service: "
    answer = $stdin.gets
    answer.chomp! unless answer.nil?
    if answer.nil? or answer.empty? or answer.to_i < 1 or answer.to_i > strings.length
      pfputs "Please enter a number from 1 to #{strings.length}."
    end
  end
  return answer
end

class String
  def downfirst
    # The downcased first character of the string.
    return '' if self.empty?
    return self[0,1].downcase
  end

  def proper?(acceptable = [])
    # Returns true if an answer is proper, and false if not.
    raise TypeError.new('Argument must be Array') unless acceptable.kind_of? Array
    if acceptable.empty?
      # If acceptable is empty, the answer is proper if it is
      # non-empty. Otherwise, it is improper.
      return !self.empty?
    else
      # If acceptable is non-empty, the answer is proper if its downcased first
      # letter is in acceptable.
      return acceptable.include? self.downfirst
    end
  end
end

def ask_user(prompt = '', acceptable = [], default = '', complaint = '')
  # Attempt at a generic user-interaction method. Returns a single-character
  # lowercase string. Keeps prompting the user until they respond
  # properly. 'Properly' means:
  #
  # * If 'acceptable' is nonempty, the first character of the response, when
  #   downcased, must be a member of 'acceptable'.
  #
  # * If 'acceptable' is empty, the requirement is simply that the response be
  #   non-nil and nonempty.
  #
  # This method prompts the user with 'prompt', then waits for their
  # response. If the lowercase first character of their answer isn't one of the
  # strings in 'acceptable', it prints 'complaint' and asks again (unless
  # 'acceptable' is empty, in which case it only checks whether the response is
  # nil/empty). If they just hit return or Ctrl-D, it uses 'default' (unless
  # 'default' is empty, in which case a nil/empty response is considered
  # improper).
  #
  # 'acceptable' must be an array of single-character, lowercase strings. It
  # can be nil or empty, in which case the user response is only checked to see
  # whether it is itself nil or empty.
  #
  # 'default' must also be a single-character, lowercase string, and it must be
  # equal to one of the members of 'acceptable' (unless 'acceptable' is nil or
  # empty). If 'default' is set and the user responds with a nil or empty
  # string, this method supplies the value of 'default'.

  def response_string(acceptable = [], default = '')
    # Return a string of acceptable responses given the values of acceptable
    # and default.
    if acceptable.empty?
      if default.empty?
        return ''
      else
        return "default=#{default}"
      end
    else
      if default.empty?
        responses = acceptable.sort
      else
        responses = acceptable.sort do |a, b|
          if a == default
            -1
          elsif b == default
            1
          else
            a <=> b
          end
        end.map do |x|
          if x == default
            x.upcase
          else
            x
          end
        end
      end
      return responses.join('/')
    end
  end

  raise TypeError.new("'prompt' must be an array") unless prompt.kind_of? String
  raise TypeError.new("'acceptable' must be an array") unless acceptable.kind_of? Array
  if acceptable.length > 0
    raise TypeError.new("'acceptable' array must consist of strings") if acceptable.any? { |x| !x.kind_of? String }
    raise ArgumentError.new("'acceptable' array must consist of single-character strings") if acceptable.any? { |x| x.length > 1 }
    raise ArgumentError.new("'acceptable' array's strings must all be lowercase") if acceptable.any? { |x| x.downcase != x }
  end
  raise TypeError.new("'default', if given, must be a string") unless default.kind_of? String
  unless default.empty?
    raise ArgumentError.new("'default', if given, must be a single-character string") if default.length > 1
    raise ArgumentError.new("'default', if given, must be lowercase") if default.downcase != default
    unless acceptable.empty?
      raise ArgumentError.new("'default', if given, must be found in 'acceptable'") unless acceptable.include? default
    end
  end
  raise TypeError.new("'complaint' must be an array") unless complaint.kind_of? String
  answer = ''
  until answer.proper?(acceptable)
    print "#{$pfx}>>> "
    if prompt.empty?
      respstr = response_string(acceptable, default)
      promptarr = ['Your choice', "(#{respstr})"]
      print "#{promptarr.join(' ')}? "
    else
      print "#{prompt} "
    end
    answer = $stdin.gets
    answer.chomp! unless answer.nil?
    unless default.empty?
      answer = default if answer.nil? or answer.empty?
    end
    answer = answer.downfirst
    unless answer.proper?(acceptable)
      if complaint.empty?
        pfputs 'Improper answer.'
      else
        pfputs complaint
      end
    end
  end
  return answer
end

def get_service(shorthost, services)
  # Make a guess at the service.
  case shorthost
  when 'oasis-login-sl6', 'puppet-test'
    # All hostnames that should pass through unchange to service
    service = shorthost
  when 'nukufetau'
    # The main hostname is nukufetau, but it's aliased as backup.
    service = 'backup'
  when 'funafuti', /^ds-bl-\d+$/
    # LDAP/directory server
    service = 'ds'
  when 'bundy', 'riley'
    # These are aliased as 'is1' and 'is2' in DNS, but whether the machines
    # call themselves this is machine-dependent.
    service = 'is'
  when 'dahmer'
    # To distinguish from 'rsv'
    service = 'rsv-old'
  when 'freeman', 'huey', 'woodcrest', /^devm\d+$/
    # Why we went with devmXX rather than vm-itbXX, I have no idea.
    service = 'vm'
  when 'xd-login', 'vanheusen'
    # These are both really xd-login
    service = 'xd-login'
  when /^yum-internal/
    # All the yum-internals violate the rules; that's my fault really; sorry
    # about that (TJL)
    service = 'yum-internal'
  when /^adeximo/, /^cpipes/, /^ece/, /^echism/, /^kagross/, /^mvkrenz/, /^rquick/, /^schmiecs/, /^soichi/, /^steige/, /^thomlee/, /^vjneal/
    # Staff VMs
    service = 'staff'
  else
    # The general case -- ideally all should fit here, and ideally this regexp
    # should be simpler
    service = shorthost.sub(/(-|-dev|-int|-itb|-test)?\d*$/, '')
  end

  # If service is 'interjection' or 'stemcell', or empty/nil, even after all
  # that, prompt the user for the service. If we found a prospective service,
  # ask the user if it's correct, and if it isn't, prompt the user for the
  # service.
  promptuser = false
  if service.nil? or service.empty? or service == 'interjection' or service == 'stemcell'
    promptuser = true
  else
    pfputs "Guessing service = '#{service}'."
    answer = ask_user 'Is this correct (Y/n/q)?', ['y', 'n', 'q'], 'y', 'We need a yes or no (q=quit).'
    if answer == 'q'
      pfputs "Exiting by user request."
      exit 0
    end
    promptuser = true if answer == 'n'
  end

  if promptuser
    # Looks like the user must select the service. For each directory other than
    # 'common' in the same directory this script is in, print an entry for the
    # user to choose from.
    answer = choose_from_array services
    service = services[answer.to_i - 1]
  end
  return service
end

def get_instance(shorthost, service, inv_data)
  # Similarly for the instance.
  instance = $opt[:instance] if $opt[:instance]
  instance = shorthost unless instance
  promptuser = false
  if instance.nil? or instance.empty?
    promptuser = true
  else
    pfputs "We have instance = '#{instance}'."
    answer = ask_user 'Is this correct (Y/n/q)', ['y', 'n', 'q'], 'y', 'We need a yes or no here (q to quit).'
    if answer == 'q'
      pfputs "Exiting by user request."
      exit 0
    end
    promptuser = true if answer == 'n'
  end

  if promptuser
    # Looks like the user must select the instance.
    instances = inv_data[service].keys
    if instances.length == 0
      pfputs "No explicit instances defined; using #{service}"
      instance = service
    elsif instances.length == 1
      pfputs "Only one instance defined; using #{instances[0]}"
      instance = instances[0]
    else
      answer = choose_from_array instances
      instance = instances[answer.to_i - 1]
    end
  end
  return instance
end

def find_inventory_file(instance)
  # Looks through Ansible inventory files in the ansible directory (must be
  # named ansible/*.inv) and finds the file that contains the given
  # instance. Raises an exception if the instance is in more than one inventory
  # file. Returns nil if not found.
  savedir = Dir.pwd
  files = Array.new
  begin
    Dir.chdir "#{$DIR}/ansible"
  rescue
    pfputs "Problem cding to ansible directory '#{$DIR}': #{$!}"
    exit 1
  end
  dh = Dir.open "."
  dh.each do |file|
    next if file =~ /^\./
    next unless file =~ /\.inv$/
    fh = File.open file, 'r'
    until fh.eof?
      line = fh.gets.chomp
      if line.start_with? "#{instance}."
        files.push file
        break
      end
    end
    fh.close
  end
  Dir.chdir savedir
  if files.length > 1
    raise InventoryError.new("Instance '#{instance}' found in more than one Ansible inventory file (#{files.join(', ')})")
  elsif files.length == 0
    raise InventoryError.new("Instance '#{instance}' not found in any Ansible inventory file")
  else
    return files[0]
  end
end

def call_ansible(service, instance)
  # Determine whether the Ansible playbook ansible/<service>.yaml exists and run
  # it if it does. This will run any and all Ansible rules including (if it's a
  # VM) creating the VM.

  savedir = Dir.pwd
  # Try to cd to ansible.
  begin
    Dir.chdir "#{$DIR}/ansible"
  rescue
    pfputs "Problem cding to ansible directory: #{$!}"
    exit 1
  end

  # Put a command together to run the playbook.
  begin
    invfile = find_inventory_file instance
  rescue InventoryError => exc
    pfputs "Error: #{exc.message}"
    pfputs "Unable to continue."
    exit 1
  end

  ansopts = Array.new
  ansopts.push '--check' if $opt.key? :test

  # If --vmhost was used on the command line, create a "-e 'vmhost=<vmhost>'"
  # option so Ansible can override the vmhost variable.
  ansopts.push "-e 'vmhost=#{$opt[:vmhost]}'" if $opt.key? :vmhost

  # If --vmversion was used on the command line, create a "-e
  # 'vmversion=<vmversion>'" option so Ansible can override the vmversion
  # variable.
  ansopts.push "-e 'vmversion=#{$opt[:vmversion]}'" if $opt.key? :vmversion

  # If there is a $vault_pw_file, use it to decrypt any passwords.
  ansopts.push "--vault-password-file=#{$vault_pw_file}" if File.exists? $vault_pw_file

  # If the user used the -d command-line option, ask Ansible for extra output
  ansopts.push '-vvv' if $opt.key? :debug

  cmd = "ansible-playbook #{ansopts.join ' '} -K -i #{invfile} -l #{instance}.grid.iu.edu #{service}.yaml"
  debug_puts "Ansible cmd: #{cmd}"
  pfputs "Running Ansible ..."
  system cmd
  if $?.exitstatus == 0
    pfputs "Completed successfully"
  else
    pfputs "Failed"
  end
  Dir.chdir savedir
end

def call_scripts(service, instance)
  # Now we'll run scripted/<service>/install (may run
  # scripted/<service>/<instance>/install, if such a script exists) and
  # scripted/common/install (may run other scripts in scripted/common). Put
  # service and instance into the environment so these scripts (whatever
  # language they're written in, which could be anything) can get
  # them. Prepending "INSTALL_" to the names in the environment so they won't
  # disrupt other things that might use environment variables 'SERVICE',
  # 'INSTANCE', etc.
  #
  # This is the definitive list of environment variables provided to the other
  # scripts.

  ENV['INSTALL_SERVICE'] = service
  ENV['INSTALL_INSTANCE'] = instance
  ENV['INSTALL_DEBUG_MODE'] = '1' if $opt.key? :debug
  ENV['INSTALL_TEST_MODE'] = '1' if $opt.key? :test
  ENV['INSTALL_VM_HOST'] = $opt[:vmhost] if $opt.key? :vmhost
  ENV['INSTALL_VM_VERSION'] = $opt[:vmversion] if $opt.key? :vmversion

  savedir = Dir.pwd
  [
    "#{$DIR}/scripted/common",
    "#{$DIR}/scripted/#{service}",
    "#{$DIR}/scripted/#{service}/#{instance}",
  ].each do |spath|
    if File.exists? spath and File.executable? spath and File.exists? "#{spath}/install" and File.executable? "#{spath}/install"
      puts
      pfputs "Running #{spath}/install

"
      Dir.chdir spath
      system "./install"
    end
  end
  Dir.chdir savedir
end

###############################################################################
# Main Program
###############################################################################

inv_data = gather_ansible_inv_data
services = gather_ansible_services inv_data
hostname = parse_options
shorthost = get_short_host hostname
ensure_shorthost_exists shorthost
service = get_service shorthost, services
instance = get_instance shorthost, service, inv_data
if is_vm_according_to_dns? shorthost
  vm_data = gather_vm_data
  find_vm_irregularities instance, vm_data
end
call_ansible service, instance
call_scripts service, instance
