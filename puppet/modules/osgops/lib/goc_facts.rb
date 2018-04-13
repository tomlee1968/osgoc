# goc_facts.rb -- adds facts of interest to the OSG Operations Center

require 'ipaddr'

def exec_ip(arguments)
  out = `ip #{arguments}`.chomp
end

def get_ip_link_show
  output = exec_ip("link show")
end

def get_interfaces
  return [] unless output = get_ip_link_show()
  output.scan(/^\d+:\s*.*:/).collect { |i| i.sub(/^\d+:\s*/, '').sub(/:.*$/, '') }.uniq
end

def get_ip_addr_show
  output = exec_ip("-o addr show")
end

def get_interface_data
  # Gets information about each interface's IP address.
  #
  # Results in a hash of hashes that looks like this ("eth0" and "eth1" may
  # vary):
  #
  # {
  #   "lo" => {
  #     "ipv4" => <IPAddr object for "127.0.0.1">,
  #     "ipv6" => <IPAddr object for "::1">,
  #   },
  #   "eth0" => {
  #     "ipv4" => <IPAddr object>,
  #     "ipv6" => <IPAddr object>,
  #   },
  #   "eth1" => {
  #     "ipv4" => <IPAddr object>,
  #     "ipv6" => <IPAddr object>,
  #   },
  # }
  interfaces = get_interfaces
  output = get_ip_addr_show
  interface_data = Hash.new { |intf, ipv| intf[ipv] = Hash.new(&intf.default_proc) }
  interfaces.each do |interface|
    lines = output.scan(/^\d+:\s*#{interface}:?.*$/).collect { |i| i.sub(/^\d+:\s*/, '').sub('\\', '').sub(/^#{interface}:?\s*/, '') }
    inet = lines.select { |i| i =~ /^inet\s/ }.collect { |i| i.sub(/^inet\s+((\d+\.){3}\d+).*$/, '\1') }
    if inet.count > 0
      interface_data[interface]["ipv4"] = IPAddr.new(inet[0])
    end
    inet6 = lines.select { |i| i =~ /^inet6\s/ }.collect { |i| i.sub(/^inet6\s+([\da-f:]+).*$/, '\1') }.reject { |i| i =~ /^fe80:/ }
    if inet6.count > 0
      interface_data[interface]["ipv6"] = IPAddr.new(inet6[0])
    end
  end
  interface_data
end

$goc_interface_data = get_interface_data

def get_subnet_interfaces
  # Gets information about which interface is connected to which GOC subnet
  # ("pub" and "priv").
  #
  # Results in a hash that looks like this (interface names will vary, as that
  # is the point of looking this up rather than hardcoding them):
  #
  # {
  #   "pub" => "eth0",
  #   "priv" => "eth1",
  # }
  goc_pfx = {
    "pub4" => IPAddr.new("129.79.53.0/24"),
    "pub6" => IPAddr.new("2001:18e8:2:6::/64"),
    "priv4" => IPAddr.new("192.168.96.0/22"),
    "priv6" => IPAddr.new("fd2f:6feb:37::/48"),
  }

  result = Hash.new { }
  ["pub", "priv"].each do |net|
    $goc_interface_data.select{ |intf, ip| intf != "lo" }.each do |intf, ip|
      if ip.key?("ipv6") and goc_pfx[net + "6"].include?(ip["ipv6"])
        result[net] = intf
        break
      elsif ip.key?("ipv4") and goc_pfx[net + "4"].include?(ip["ipv4"])
        result[net] = intf
        break
      end
    end
  end
  result
end

$goc_subnet_interface = get_subnet_interfaces

# For the purposes of determining which LDAP group the host should be governed
# by, we need a 'goc_accesshost' fact -- most of the time this just takes any
# digits off the end of the short hostname and any hyphen that may appear
# before that (for example, tx-itb1 becomes tx-itb, glidein-itb stays
# glidein-itb, is1 and is2 become is, etc.), but there are a few special cases,
# and puppet-test becomes 'blimfquark' because it's an unlikely string to
# appear accidentally.
Facter.add('goc_accesshost') do
  setcode do
    hostname = Facter.value(:hostname)
    case hostname
    when 'oasis-login-sl6'
      # For cases where goc_accesshost should simply be identical to hostname,
      # but where the default regex substitution would mangle it
      hostname
    when 'nukufetau'
      'backup'
    when 'puppet-test'
      # If you see this, which is unlikely to happen by accident, you know this
      # code is working
      'blimfquark'
    when 'freeman', 'huey', 'woodcrest'
      'devm'
    when /^psvm\d+$/
      'psvm'
    when 'bundy', 'riley'
      'is'
    when 'puppet'
      'puppet'
    when 'dahmer'
      # To distinguish it from 'rsv' (as in rsv1, etc.)
      'rsv-old'
    when 'xd-login', 'vanheusen', 'osg-flock', 'leonard'
      'osg-xd'
    when /^yum-internal/
      # Almost every yum-internal would be mangled by the default regex
      # substitution
      'yum-internal'
    else
      hostname.sub(/-?\d+$/, '')
    end
  end
end

# A true-or-false fact that just answers the question of whether a machine is
# or is not a virtualization host.  Currently that's just a question of whether
# libvirtd is enabled.
Facter.add('is_goc_vmhost') do
  setcode do
    osfamily = Facter.value(:osfamily)
    majver = Facter.value(:lsbmajdistrelease)
    case osfamily
    when /RedHat/
      if majver.to_i < 7
        if !Dir.glob('/etc/rc3.d/S*libvirtd').empty?
          'true'
        else
          'false'
        end
      else
        if File.exist? '/etc/systemd/system/multi-user.target.wants/libvirtd.service'
          'true'
        else
          'false'
        end
      end
    end
  end
end

# Many Puppet rules depend on what OSG Operations service a host is running,
# whether it's ITB or not -- ITB instances should act the same as the
# production instances so they're valid testbeds.  This returns what OSG
# service the host is supposedly an instance of, based on its short hostname --
# 'is1', 'is2', and 'is-itb1' all become 'is', 'perfsonar1', 'perfsonar2', and
# 'perfsonar-itb' all become 'perfsonar', etc.
Facter.add('goc_service') do
  setcode do
    hostname = Facter.value(:hostname)
    case hostname
    when 'oasis-login-sl6'
      # For hosts whose names end in a number
      hostname
    when 'nukufetau'
      'backup'
    when 'funafuti', /^ds-bl-\d+$/
      'ds'
    when 'bundy', 'riley'
      'is'
    when 'dahmer'
      # To distinguish from 'rsv'
      'rsv-old'
    when 'freeman', 'huey', 'woodcrest', /^devm\d+$/, /^psvm\d+$/
      # Why we went with devmXX instead of vm-itbXX, I have no idea
      'vm'
    when 'xd-login', 'vanheusen'
      'xd-login'
    when /^yum-internal/
      # Almost every yum-internal breaks the pattern:
      # yum-internal-5-32, yum-internal-6, yum-internal-c6, yum-internal-c7
      'yum-internal'
    when 'puppet-test'
      'puppet-test'
    else
      hostname.sub(/(-|-dev|-int|-itb|-test)?\d*$/, '')
    end
  end
end

Facter.add('goc_intf_pub') do
  # Returns the name of the interface connected to the GOC public network.
  setcode do
    $goc_subnet_interface["pub"] or ""
  end
end

Facter.add('goc_intf_priv') do
  # Returns the name of the interface connected to the GOC private network.
  setcode do
    $goc_subnet_interface["priv"] or ""
  end
end

Facter.add('goc_ipv4_pub') do
  # Returns the IPv4 address currently defined for the interface on the GOC
  # public network (vlan 259, which has been assigned 129.79.53.0/24).
  setcode do
    result = nil
    if $goc_subnet_interface.key?("pub")
      intf = $goc_subnet_interface["pub"]
      if $goc_interface_data.key?(intf) and $goc_interface_data[intf].key?("ipv4")
        result = $goc_interface_data[intf]["ipv4"]
      end
    end
    result.to_s
  end
end

Facter.add('goc_ipv6_pub') do
  # Returns the IPv6 address currently defined for the interface on the GOC
  # public network (vlan 259, which has been assigned 2001:18e8:2:6::/64).
  setcode do
    result = nil
    if $goc_subnet_interface.key?("pub")
      intf = $goc_subnet_interface["pub"]
      if $goc_interface_data.key?(intf) and $goc_interface_data[intf].key?("ipv6")
        result = $goc_interface_data[intf]["ipv6"]
      end
    end
    result.to_s
  end
end

Facter.add('goc_ipv4_priv') do
  # Returns the IPv4 address currently defined for the interface on the GOC
  # private network (vlan 4020, which uses 192.168.96.0/22).
  setcode do
    result = nil
    if $goc_subnet_interface.key?("priv")
      intf = $goc_subnet_interface["priv"]
      if $goc_interface_data.key?(intf) and $goc_interface_data[intf].key?("ipv4")
        result = $goc_interface_data[intf]["ipv4"]
      end
    end
    result.to_s
  end
end

Facter.add('goc_ipv6_priv') do
  # Returns the IPv6 address currently defined for the interface on the GOC
  # private network (vlan 4020, which uses fd2f:6feb:37::/48).
  setcode do
    result = nil
    if $goc_subnet_interface.key?("priv")
      intf = $goc_subnet_interface["priv"]
      if $goc_interface_data.key?(intf) and $goc_interface_data[intf].key?("ipv6")
        result = $goc_interface_data[intf]["ipv6"]
      end
    end
    result.to_s
  end
end
