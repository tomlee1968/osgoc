#!/usr/bin/python

# Set up the appropriate Munin "ip_" plugins
# Tom Lee <thomlee@iu.edu>
# Begun 2015-10-26

# Look at the host's network interfaces to find all the IP addresses on which
# Munin should monitor traffic, then set up Munin to do so.  Check first, and
# if it's already set up that way, do nothing.

# This script was originally a couple of Puppet rules, but they were
# complicated enough that I made them a separate script run by cron.

import os, re, string, sys
from glob import glob
from IPy import IP
from subprocess import Popen, PIPE

# Munin "ip_" plugins whose IPs don't fall into one of these prefixes won't be
# affected:
prefixes = [
    IP("129.79.53.0/24"),
    IP("192.168.96.0/22"),
    IP("2001:18e8:2:6::/64"),
    IP("fd2f:6feb:37::/48"),
    ]

# Munin plugins directory:
plugindir = "/etc/munin/plugins"
pluginsrcdir = "/usr/share/munin/plugins"

def in_any(theObject, theList):
    """Returns True if theObject is in any of the containers in theList, and
    False if not.
    
    """
    for myList in theList:
        if theObject in myList:
            return True
    return False

def munin_ip_addrs():
    """Return the IP addresses Munin is monitoring now.
    
    """
    return map(lambda x: IP(x), \
                   map(lambda x: re.sub("^.*_", "", x), \
                           glob("%s/ip_*" % plugindir)))

def munin_ip_addrs_in_prefixes():
    """Return the IP addresses Munin is monitoring now that are in any of the
    prefixes in the global prefixes aray.
    
    """
    return sorted( \
        filter(lambda x: in_any(x, prefixes), munin_ip_addrs()), \
            key = lambda x: x.int())

def run_command(cmd):
    """Run a shell command and return its output as a list of strings.
    
    """
    lines = Popen(cmd.split(), stdout = PIPE).communicate()[0].split("\n")
    output = filter(lambda x: x, lines)
    return output

def used_ip_addrs():
    """Return a list of the IP addresses currently in use on this machine.
    
    """
    return map(lambda x: IP(x), \
                   map(lambda x: re.sub("^.*inet[0-9]* +([^ /]+).*$", "\g<1>", x), \
                           filter(lambda x: re.search("inet", x) \
                                      and not re.search("secondary", x) \
                                      and not re.search("scope link", x), \
                                      run_command("/sbin/ip -o addr show"))))

def real_used_ip_addrs():
    """Return a list of the IP addresses currently in use on this machine that
    aren't localhost or link-local.
    
    """
    return filter(lambda x: x not in IP("127.0.0.0/8") \
                      and x not in IP("::1/128"), \
                      used_ip_addrs())

def real_used_ip_addrs_in_prefixes():
    """Return a list of the IP addresses currently in use on this machine that
    aren't localhost or link-local that are in prefixes.
    
    """
    return sorted( \
        filter(lambda x: in_any(x, prefixes), real_used_ip_addrs()), \
            key = lambda x: x.int())

def get_iptables_rules(version, table, chain):
    """Gets the iptables rules for the given IP version, table, and chain.
    
    Returns the iptables rules for the given IP version, table, and
    chain.  The rules are given as a list of dictionaries, one
    dictionary per rule, with the following keys:

    target: The target chain, if any (None if none)
    prot: The protocol to affect, or 'all' if all
    opt: Any options, or '--' if none
    source: The source IP address/mask the rule matches
    destination: The destination IP address/mask the rule matches
    other: Any other requirements such as state or port

    Arguments:

    version (int or string): 4, 6, '4', or '6'
    table (string): 'filter', 'nat', 'mangle', or 'raw'
    chain (string): the name of any builtin or user-defined chain"""
    
    # Chain INPUT (policy DROP)
    # target     prot opt source               destination
    #            all  --  0.0.0.0/0            129.79.53.70
    #            all  --  0.0.0.0/0            192.168.97.26

    version_str = str(version)
    if version_str != '4' and version_str != '6':
        raise ValueError("Version must be '4' or '6'")
    if table not in ['filter', 'mangle', 'nat', 'raw']:
        raise ValueError("Table must be 'filter', 'mangle', 'nat', or 'raw'")
    executable = {'4': 'iptables', '6': 'ip6tables'}
    command = "/sbin/%s -t %s -nL %s" % (executable[version_str], table, chain)
    try:
        lines = run_command(command)
    except OSError, err:
        print "Unable to get %s lines: %s" % \
              (executable[version_str], err.args[1])
        return []
    output = []
    # Get rid of the two header lines
    del lines[0:2]
    for line in lines:
        # Normally in ip6tables you get 5 fields (for a maximum list
        # index of 4).
        max_fields = 4

        # However, in the IPv4 case, iptables prints an empty 'opt'
        # field (which I've never seen used by either iptables or
        # ip6tables) as '--', whereas ip6tables only prints empty
        # space.  Split with one more field, then discard the '--'
        # later.
        if version_str == '4':
            max_fields += 1

        # If the line starts with a space, there is no target chain
        # (as in the rules that we are actually looking for in this
        # script as a whole).  However, splitting the string will thus
        # result in one fewer field, so use a max_fields one smaller
        # and insert a None field at the start of the list.
        if line[0] == ' ':
            max_fields -= 1

        # Do the actual split now that max_fields is decided.
        values = string.split(line.strip(), None, max_fields)

        # Here's the other half of what we need to do for generic rules.
        if line[0] == ' ':
            values.insert(0, None)

        # Here's the other half of what we need to do for iptables.
        if version_str == '4':
            del values[2]

        # Now that all our field wrangling has resulted in what I hope
        # is a guaranteed 5-element list, zip it into a dictionary.
        value = dict(zip(['target', 'prot', 'source', 'destination', 'other'], \
                         values))

        # Convert the source and destination IPs into IP objects.
        value['source'] = IP(value['source'])
        value['destination'] = IP(value['destination'])
        output.append(value)
    return output

def get_generic_iptables_rules(version, table, chain):
    """Gets the generic (no target, any protocol) iptables rules
    for the given IP version, table, and chain.

    Not sure whether it's 'official' terminology, but for the purposes
    of this script a 'generic iptables rule' is an iptables rule with no
    designated target whose protocol is 'any'."""
    return filter(lambda x: x['target'] == None and x['prot'] == 'all', \
                  get_iptables_rules(version, 'filter', chain))

def add_generic_iptables_rule(version, table, chain, ip):
    """Add a generic iptables rule.
    
    For the given IP version ('4' or '6'), iptable, chain, and IP
    address, insert a generic iptables rule at the beginning of the
    chain."""
    
    version_str = str(version)
    if version_str != '4' and version_str != '6':
        raise ValueError("Version must be '4' or '6'")
    if table not in ['filter', 'mangle', 'nat', 'raw']:
        raise ValueError("Table must be 'filter', 'mangle', 'nat', or 'raw'")
    executable = {'4': 'iptables', '6': 'ip6tables'}
    whicharg = {'INPUT': '-d', 'OUTPUT': '-s'}
    command = "/sbin/%s -t %s -I %s 1 %s %s" % \
              (executable[version], table, chain, whicharg[chain], ip)
    try:
        run_command(command)
    except OSError, err:
        print "Unable to add rules to %s: %s" % \
              (executable[version_str], err.args[1])

def delete_generic_iptables_rule(version, table, chain, ip):
    """Delete a generic iptables rule.
    
    For the given IP version ('4' or '6'), iptable, chain, and IP
    address, delete a generic iptables rule from the chain."""
    
    version_str = str(version)
    if version_str != '4' and version_str != '6':
        raise ValueError("Version must be '4' or '6'")
    if table not in ['filter', 'mangle', 'nat', 'raw']:
        raise ValueError("Table must be 'filter', 'mangle', 'nat', or 'raw'")
    executable = {'4': 'iptables', '6': 'ip6tables'}
    whicharg = {'INPUT': '-d', 'OUTPUT': '-s'}
    command = "/sbin/%s -t %s -D %s %s %s" % \
              (executable[version], table, chain, whicharg[chain], ip)
    try:
        run_command(command)
    except OSError, err:
        print "Unable to delete rules from %s: %s" % \
              (executable[version_str], err.args[1])

def ensure_iptables_rules_ipv_chain(ipv, chain, addrs):
    """Makes sure the IP monitoring rules in the given chain in the
    given IPV firewall match the given list of IP addresses.

    In order for Munin to be able to monitor IP traffic, the iptables
    and ip6tables firewalls need to have rules that 'see' packets
    traveling to/from a given IP address.  The commands to create
    these rules look like

    # iptables -t filter -A INPUT -d <address>/<mask>
    # iptables -t filter -A OUTPUT -s <address>/<mask>

    where <address> is the IP address in question and <mask> is a
    bitmask specifying a complete match (i.e. 32 for IPv4 and 128 for
    IPv6).  Substitute 'ip6tables' for 'iptables' in the IPv6 case.
    Note that there is no -j flag; the firewall is not meant to take
    any action when encountering these packets.  It just notices them
    so it can tally the total amount of data going to and from the
    given address."""

    # For INPUT, match destinations; for OUTPUT, match sources
    field = {'INPUT': 'destination', 'OUTPUT': 'source'}

    # Make a subset of the given addrs containing only the addresses
    # for the given IP version.
    ipv_addrs = filter(lambda addr: str(addr.version()) == ipv, addrs)

    # Get the existing generic rules for ipv and chain, and filter
    # out any that don't match any of the prefixes in the global
    # prefixes array -- those must have been put there by something
    # else.
    existing = filter(lambda x: in_any(x[field[chain]], prefixes), \
                      get_generic_iptables_rules(ipv, 'filter', chain))

    # Look for an existing rule that has addr in the appropriate field
    # for the chain.  If it's not found, remember it.
    needed = filter(lambda addr: \
                    not filter(lambda rule: \
                               rule[field[chain]] == addr, \
                               existing), \
                    ipv_addrs)

    # Look at the existing rules and find any whose appropriate-field
    # IPs aren't in addrs.
    unneeded = filter(lambda addr: addr not in ipv_addrs, \
                      map(lambda rule: rule[field[chain]], existing))

    # Add the needed; delete the unneeded.
    for ip in needed:
        add_generic_iptables_rule(ipv, 'filter', chain, ip)
    for ip in unneeded:
        delete_generic_iptables_rule(ipv, 'filter', chain, ip)

def ensure_iptables_rules(addrs):
    """Makes sure the IP monitoring rules in the firewall match the
    given list of IP addresses.

    In order for Munin to be able to monitor IP traffic, the iptables
    and ip6tables firewalls must have 'generic' rules that notice
    packets traveling to/from this server's IP address(es).  See
    ensure_iptables_rules_ipv_chain for more information."""

    # Ensure the rules for each IP version and for both INPUT and
    # OUTPUT chains in the filter table.
    for ipv in ['4', '6']:
        for chain in ['INPUT', 'OUTPUT']:
            ensure_iptables_rules_ipv_chain(ipv, chain, addrs)

def delete_munin_ip(ip):
    """Delete an IP from Munin monitoring.
    
    Munin monitors an IP if there exists a symlink at
    <plugindir>/ip_<address> pointing to <pluginsrcdir>/ip_.  Given
    <address>, this function deletes such a symlink if it exists.
    Changes in Munin's plugins require a restart of munin-node for
    them to take effect; this function does not do that."""
    
    try:
        os.unlink("%s/ip_%s" % (plugindir, ip))
    except OSError, err:
        print "Error while attempting to delete %s/ip_%s: %s" % \
            (plugindir, ip, err.strerror)

def create_munin_ip(ip):
    """Tell Munin to start monitoring an IP.
    
    Munin monitors an IP if there exists a symlink at
    <plugindir>/ip_<address> pointing to <pluginsrcdir>/ip_.  Given
    <address>, this function creates such a symlink if it doesn't
    already exist.  Changes in Munin's plugins require a restart of
    munin-node for them to take effect; this function does not do
    that."""
    
    try:
        os.symlink("%s/ip_" % pluginsrcdir, "%s/ip_%s" % (plugindir, ip))
    except OSError, err:
        print "Error while attempting to symlink %s/ip_ as %s/ip_%s: %s" % \
            (pluginsrcdir, plugindir, ip, err.strerror)

muninaddrs = munin_ip_addrs_in_prefixes()
#for ip in muninaddrs:
#    print ip

realaddrs = real_used_ip_addrs_in_prefixes()
#for ip in realaddrs:
#    print ip

ensure_iptables_rules(realaddrs)

if muninaddrs == realaddrs:
#    print "No need to change Munin plugin symlinks"
    sys.exit(0)

# Have Munin stop monitoring any IPs that don't exist.
for munin_ip in muninaddrs:
    if munin_ip not in realaddrs:
        delete_munin_ip(munin_ip)

# Have Munin start monitoring any existing IPs that aren't monitored already.
for real_ip in realaddrs:
    if real_ip not in muninaddrs:
        create_munin_ip(real_ip)

# If we're here, things changed, so make sure the rest of the system adjusts
if os.path.exists("/bin/systemctl"):
    run_command("/bin/systemctl restart munin-node.service")
else:
    run_command("/sbin/service munin-node restart")
