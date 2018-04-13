#!/usr/bin/python

# convert_to_gociptables_v6.py
# Convert nonglobal GOC iptables scripts to gociptables IPv6 format
# Tom Lee <thomlee@iu.edu>
# Begun 2014-05-02
# Last modified 2014-05-09

# In the transition from gociptables v1.5 to 1.6, which brings in IPv6
# compatibility, I have renamed the existing shortcut environmental variables
# and introduced new ones with the old names.  For example, we have $ITFAI,
# which stands for the frequently-used command "iptables -t filter -A INPUT".
# I have renamed this variable to $ITFAI4 (since it is using IPv4) and created
# a new $ITFAI that stands for "ip6tables -t filter -A INPUT".

# In Linux's netfilter, the IPv6 firewall is analogous to the IPv4 firewall but
# separate.  The IPv4 firewall is manipulated via the iptables command, while
# the IPv6 firewall has the ip6tables command.  The only differences are:

# Difference 1: No NAT.  The IPv4 netfilter has tables "filter", "mangle",
# "nat", and "raw".  The IPv6 netfilter has only "filter", "mangle", and "raw"
# -- this is because Network Address Translation (NAT) as we know it does not
# exist in IPv6.  Fortunately we barely use NAT; the only machine that might
# use it is vpn.grid, and without looking at it I don't think it does.

# Difference 2: ICMP is now ICMPv6.  Any iptables rule that referred to
# protocol 'icmp' needs to be changed to use 'icmp6'.  The 'icmp6' extension to
# ip6tables works just like the 'icmp' extension to iptables, but the
# '--icmp-type' option has to be changed to '--icmpv6-type'.  Common ICMP
# packet types all have analogues in ICMPv6, usually with the same names within
# ip6tables as they had in iptables.

# So basically everywhere we created an iptables rule, we need to create an
# identical ip6tables rule.  Everywhere we created an iptables subchain, we
# need to create an identical ip6tables subchain.  Everywhere one of those
# iptables subchains was called from one of iptables's builtin chains, the
# corresponding ip6tables subchain needs to be called from the corresponding
# builtin chain in ip6tables.

# The only exception to this is when we don't have IPv6 addresses for
# something.  We can't yet define a convenient subchain to permit all packets
# from the IU-Secure IP ranges when we don't know the IPv6 addresses for those
# ranges.  We can't define a subchain to allow packets from Chris's workstation
# when it has an IPv4 address but no IPv6 address yet.  So ip6tables rules that
# depend on the source IP address will have to be omitted for now until there
# are IPv6 addresses for those source hosts and we know what they are.

# I suppose I could have just created new variables of the $ITFAI6 sort and
# left the $ITFAI ones alone, but I didn't, and it's already changed, so I'm
# not going through and changing it back everywhere, probably causing more
# problems.  I think the way I did it was more forward-thinking anyway; the
# time will come one day when IPv4 will be abandoned, and for many years before
# that, IPv4 will be looked upon as the old, fading protocol that we still
# support because legacy devices still demand it.  It will be like ISA cards
# and IDE hard drives.  We won't want to have $ITFAI6 variables lying around
# then.  "What's the 6 for?" someone will ask.  "Nobody uses IPv4 anymore, so
# isn't the 6 just extra typing?"

# Anyway, I've changed all the global scripts by hand, and those will change in
# stemcell and Puppet once I release the change to ITB/production, but the
# problem is that there are a lot of nonglobal scripts that are specific to
# each host/service.  I need a script to automatically do the following:

# 1. Go through the files in /etc/iptables.d, which will still contain all the
# firewall definition commands, for both iptables and ip6tables.  Ignore any
# scripts with "-global-" in their filenames.  Ignore any scripts whose
# filenames don't start with two digits.  Ignore any scripts that aren't set
# executable.  And ignore any that already have $IT*4 variables appearing in
# them -- obviously they've been transitioned already (possibly by this script,
# possibly by hand).  For any script that hasn't been skipped:

# 2. When there is an $ITFAI-type rule, rename it to $ITFAI4 or the equivalent,
# leaving an $ITFAI-type copy unless it's a NAT rule ($ITN*).  $ITN* rules get
# renamed but not copied.  If there's a rule that refers to an IPv4 address or
# range, just rename it; don't copy it.  We might want to send a notification
# to someone (like the friendly neighborhood sysadmin), because the service
# might depend on this rule, but we would need to know the equivalent IPv6
# address/range in order to make it work, and that requires some research.
# Addendum: If the rule refers to an IPv4 address, rename without copying just
# as if it were a NAT rule, because in almost all cases we don't have an IPv6
# address for the same host or range.  We'll have to do those by hand later.

# 3. When the script uses "$ITF -N foo" to create a subchain, followed by
# various "$ITF -A foo ..." commands to add rules to that subchain, the whole
# subchain needs to be duplicated, and the duplicate needs to have $ITF changed
# to $ITF4.  The same goes for $ITM and $ITR.  If it's $ITN, however, it just
# gets renamed, not duplicated.  (I think it's probably very unlikely that
# there will be any $ITN subchains, or $ITM or $ITR ones for that matter; I
# think they're all $ITF.)  Addendum: If any rules in the subchain refer to
# IPv4 addresses or ranges, leave them out.  If the subchain ends up empty, so
# be it; a subchain with no rules has no effect.  But if we don't know the
# equivalent IPv6 address or range (as is almost always the case currently), we
# can't make equivalent rules.

# I did this in Python to torture myself, and to force myself to learn some
# Python.

import os
import re
import sys
import optparse

def handle_options():
    """Handle command-line options."""
    parser = optparse.OptionParser(
        description =
"""Convert local /etc/iptables.d files into IPv6 compatible format.""",
    )
    parser.add_option(
        '-d', '--debug',
        help = "enable debug mode (extra output about what's happening)",
        action = 'store_true',
    )
    parser.add_option(
        '-t', '--test',
        help = "enable test mode (print what would be done, but don't do it)",
        action = 'store_true',
    )
    (opts, args) = parser.parse_args()
    return opts

def debug_print(string):
    """Print a string with a (DEBUG) prefix, but only if global opts.debug is True.

    """
    global opts
    if opts.debug:
        print "(DEBUG) " + string

def test_print(string):
    """Basically just print a string with a (TEST) prefix.  This gets called in
place of doing things when opts.test is True.

    """
    print "(TEST) " + string

def output_subchain(subch):
    """Given a sequence of lines, return a sequence of lines as it should be
    printed: print it twice, once with any IPv4 lines left out, once with the
    command variables 4'd.  If it's a NAT subchain, print only the 4'd version.

    """
    output = []
    itx_re = re.compile(r"(\$IT[FMNR])(?!4)")
    if not re.search(r"^[#\s]*\$ITN", subch[0]):
        for line in subch:
            if not re.search(r"\d+(\.\d+){3}", line):
                output.append(line)
    for line in subch:
        output.append(itx_re.sub(r"\g<1>4", line))
    return output

def rename_file(fn):
    """Rename the given file to fn.bak.

    Returns True on success, False on failure.

    """
    try:
        os.rename(fn, fn + ".bak")
    except OSError as e:
        sys.stderr.write("Unable to rename file %s to %s.bak: %s\n" % (fn, fn, e.strerror))
        return False
    return True

def read_file(fn):
    """Read a single file and return its contents, or None if unsuccessful."""

    contents = []
    try:
        fp = open(fn, "r")
    except IOError:
        sys.stderr.write("Unable to open file '%s'\n" % fn)
        return None
    for line in fp:
        contents.append(line)
    fp.close
    return contents

def convert_contents(contents):
    """Convert the file contents."""

    output = []
    save = []
    inter = []
    cmd = None
    chain = None
    itxay_re = re.compile(r"(\$IT[FMNR]A(F|I|O|POST|PRE))(?!4)")
    subch_re = re.compile(r"^[#\s]*(\$IT[FMNR])\s+-N\s+(\S+)\s*$")
    for line in contents:
        # If cmd is set, we're in a subchain definition
        if cmd != None:
            # See if the subchain is continuing
            app_re = \
               re.compile(r"^[#\s]*%s\s+-A\s+%s\s" % (re.escape(cmd),
                                                      re.escape(chain)))
            if app_re.search(line):
                # Adding to the cmd/chain subchain -- save the line
                save.extend(inter)
                inter = []
                save.append(line)
                continue
            # If not, is the line a comment or blank line?
            elif re.search(r"^\s*#", line) or re.search(r"^\s*$", line):
                # Add it to inter; decide what to do with it later
                inter.append(line)
                continue
            else:
                # Otherwise, the subchain is over
                output.extend(output_subchain(save))
                output.extend(inter)
                # Clear save, cmd, and chain
                save = []
                inter = []
                cmd = None
                chain = None
        # Now deal with whatever this line is
        if itxay_re.search(line):
            # It's got an $IT*A* type rule -- print unless it's $ITNA* or has
            # an IPv4 address
            if not re.search(r"^[#\s]*\$ITNA", line) \
               and not re.search(r"\d+(\.\d+){3}", line):
                output.append(line)
            # Print the "4" version of the line
            output.append(itxay_re.sub(r"\g<1>4", line))
        else:
            # See if the beginning of a subchain occurs
            subch_m = subch_re.search(line)
            if subch_m:
                # It does -- save it and start remembering it
                cmd, chain = subch_m.group(1, 2)
                save.append(line)
            else:
                # Some other line -- just print it
                output.append(line)
    if save:
        # Deal with whatever's left in save at the end
        output.extend(output_subchain(save))
        output.extend(inter)
    return output

def write_file(fn, contents):
    """Write the contents to the given filename."""
    try:
        fp = open(fn, "w")
    except IOError as e:
        sys.stderr.write("Unable to open file '%s': %s\n" % (fn, e.strerror))
        return False
    for line in contents:
        fp.write(line)
    fp.close
    return True

def copy_owners_perms(fn1, fn2):
    """Copy the ownerships and permissions from file fn1 to file fn2.

    Returns True if successful, False if not.

    """
    try:
        st = os.stat(fn1)
    except IOError as e:
        sys.stderr.write("Unable to stat file '%s': %s\n" % (fn1, e.strerror))
        return False
    try:
        os.chmod(fn2, st.st_mode)
    except IOError as e:
        sys.stderr.write("Unable to chmod file '%s': %s\n" % (fn2, e.strerror))
        return False
    try:
        os.chown(fn2, st.st_uid, st.st_gid)
    except IOError as e:
        sys.stderr.write("Unable to chown file '%s': %s\n" % (fn2, e.strerror))
        return False
    return True

def convert_file(fn):
    """Rename the file to fn.bak, read it in, write it out, and copy its
ownerships/permissions.

    """
    global opts
    # Rename the file
    if opts.test:
        test_print("Rename '%s' to '%s.bak'" % (fn, fn))
    elif not rename_file(fn):
        return False
    # Read the file
    if opts.test:
        # Leave off the ".bak" in test mode because it wasn't renamed; we still
        # really read it, because that's non-destructive
        contents = read_file(fn)
    else:
        contents = read_file(fn + ".bak")
    if not contents:
        return False
    # Convert the contents to the new format
    new_contents = convert_contents(contents)
    # Write the converted contents to a file
    if opts.test:
        # Write them to stdout in test mode
        test_print("Write '%s'" % fn)
        for line in new_contents:
            print line,
    elif not write_file(fn, new_contents):
        return False
    # Copy the ownerships/permissions from the .bak file to the new file
    if opts.test:
        test_print("Copy owners/perms from '%s.bak' to '%s'" % (fn, fn))
    elif not copy_owners_perms(fn + ".bak", fn):
        return False
    return True

###############################################################################
# Main script
###############################################################################

# Handle command-line arguments, if any
opts = handle_options()
# Go to the iptables.d directory
try:
    os.chdir("/etc/iptables.d")
except:
    sys.stderr.write("Could not cd to /etc/iptables.d")
    exit(1)
# Get a list of the filenames there
fns = os.listdir(".")
# Decide what to do with each file
for fn in fns:
    # Proper files' names start with 2 digits
    if not re.search(r"^\d\d", fn):
        debug_print("Skipped file '%s' because its name didn't start with digits" % fn)
        continue
    # Don't touch the global files
    if re.search(r"-global-", fn):
        debug_print("Skipped file '%s' because it's global" % fn)
        continue
    # Skip the non-executables (might be .rpmsave, .bak, etc.)
    if not os.access(fn, os.X_OK):
        debug_print("Skipped file '%s' because it isn't executable" % fn)
        continue
    # Skip them if they contain no mention of $ITx
    if (os.system("grep -q '\\$IT[FMNR]' " + fn) >> 8) != 0:
        debug_print("Skipped file '%s' because it doesn't mention the $ITx variables" % fn)
        continue
    # Skip if the file has even one $ITxAy4 -- it may be already converted
    if (os.system("grep -q '\\$IT[FMNR]A(F|I|O|POST|PRE)4' " + fn)) == 0:
        debug_print("Skipped file '%s' because it already has an $ITxAy4 variable" % fn)
        continue
    convert_file(fn)
exit(0)
