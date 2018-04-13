#!/usr/bin/perl

# Munin plugin skeleton
# by Tom Lee <thomlee@iu.edu
# Begun 2015-03-09
# Last modified 2015-10-20

#%# family=example

# Munin runs plugins in two different circumstances:
#
# Install time: When Munin is installed on a machine, a script called
# munin-node-configure that comes with Munin will be run.  This script will
# examine each plugin in existence on the machine for "magic markers," special
# patterns found in comments within the plugin, and based on which markers it
# finds, it may run the plugin with the command-line parameters 'autoconf',
# 'suggest', and 'snmpconf'.  More about "magic markers" later.
#
# Run time: This is what will happen most of the time this plugin is called.
# Munin-run or munin-node calls this plugin twice, once with the 'config'
# command-line parameter and once with no command-line parameters.

# 'autoconf': The munin-node-configure script looks for the magic marker
# 'capabilities=autoconf', and when it finds a plugin with that marker, it will
# run that plugin with the 'autoconf' parameter to ask the plugin whether it
# thinks it can return useful information on this machine.  The plugin author
# should write tests, the exact nature of which must of course depend on what
# the plugin is meant to monitor, to determine whether or not the plugin can do
# what it is intended to do on the machine on which it is running.  For
# example, a plugin that is meant to monitor some quantity having to do with
# Apache may want to test whether Apache is installed.  If the plugin can
# usefully run on this machine, the 'autoconf' parameter should cause it to
# print 'Yes' and return an exit value of 0.  If not, it should print 'No
# (<reason>)', where <reason> is some explanatory text, and return an exit
# value of 1.

# 'suggest': The munin-node-configure script looks for the magic marker
# 'capabilities=suggest', and when it finds a plugin with that marker, it knows
# that the plugin is a "wildcard plugin" and calls it with the 'suggests'
# parameter to ask it what symlink parameters to give it.  A wildcard plugin
# has a name ending with an underscore character ('_') and tests the symlink
# used to call it for an additional parameter that follows that final
# underscore.  For example, the 'ip_' plugin is typically symlinked as
# 'ip_<address>', where <address> is the IP address to monitor; when the plugin
# runs, it looks at the symlink used to run it, sees what follows the last
# underscore character in the symlink's file path, and uses that as the IP
# address to work with.  If the plugin is meant to be a wildcard plugin, it
# should print a list of the parameters (one per line) that it thinks it should
# be symlinked with when called with 'suggest'.  This will cause
# munin-node-configure to do this symlinking automatically.

# 'snmpconf': When run with the -snmp option, the munin-node-configure script
# looks for the magic markers 'family=snmpauto' and 'capabilities=snmpconf'.
# If it finds both of these, it knows that the plugin is an SNMP plugin and
# calls it with the 'snmpconf' parameter to ask it for more information about
# how to configure it.  An SNMP plugin can monitor a host other than the one it
# is running on .  Such a plugin's name will start with 'snmp' followed by two
# underscores and then the rest of its name (for example, 'snmp__df'); when it
# is symlinked, the host to monitor will appear between those two underscores
# (for example, 'snmp_test.example.com_df').  It may also have a final
# underscore and thus be a wildcard plugin as well.  For example, 'snmp__ip_'
# might be told to monitor eth0 on test.example.com by being symlinked as
# 'snmp_test.example.com_ip_eth0'.  If this plugin is an SNMP plugin and has
# the two above magic markers, it should respond to an 'snmpconf' parameter by
# printing one or more 'require' lines:
#
# require 1.2.3.4
# require 1.2.3.4.
# require 1.2.3.4. [0-9]
#
# where the keyword 'require' is followed by a space and an OID that must exist
# on an SNMP agent, followed by an optional regular expression.  The goal is to
# determine whether these quantities exist (and if they match the regex, if
# present), and if they do, munin-node-configure will automatically symlink the
# plugin.  If it is also a wildcard plugin, there should also be an 'index'
# line, stating the keyword 'index' and the OID of the index, and possibly a
# 'number' line as well, stating the keyword 'number' and an OID that returns
# the number of items.

# 'config': The previous parameters are rarely called, but this one is called
# extremely frequently.  Whereas the ones above are optional and exist only to
# guide the 'munin-node-configure' script, this one is essential to the
# plugin's functioning as a plugin.  It should return metadata about the data
# the plugin provides.  It should print lines consisting of a keyword, a space,
# and a value.  To see all the keywords, see the Munin documentation at
# http://munin-monitoring.org/wiki/HowToWritePlugins .  Some useful 'config'
# data to print include:
#
# graph_title Title to appear at top of graph
# graph_vlabel Graph vertical label (unit)
# graph_args --base 1000 --lower-limit 0
# graph_category Category
# graph_info Some explanatory text about the graph
# quantity1.label Brief label for quantity 'quantity1'
# quantity1.draw LINE2
# quantity1.info More descriptive explanatory text about quantity 'quantity1'
# quantity1.warning 60
# quantity1.critical 180

# (nothing): When called without any parameters, the plugin should print the
# values of the quantities it is meant to monitor.  For example:
#
# quantity1.value 3.23
# quantity2.value 2.24

# Magic markers: These are strings that appear in comments and let the
# 'munin-node-configure' script know that this plugin is able to output
# information that is of use to 'munin-node-configure' -- this plugin can tell
# that script whether and how it should be symlinked on this machine.  Magic
# markers consist of the string '#%#', a space, a keyword, an equals sign, and
# a space-separated list of values.  For example, a standard plugin that
# supports autoconf might have these lines:
#
# #%# family=auto
# #%# capabilities=autoconf
#
# A wildcard plugin might have lines like this:
#
# #%# family=auto
# #%# capabilities=autoconf suggest
#
# An SNMP plugin might have lines like:
#
# #%# family=snmpauto
# #%# capabilities=snmpconf
#
# The 'family' and 'capabilities' markers are the only two that exist.
# Possible values for 'family' (usually only one of these is used at a time):
#
# auto: signifies the plugin can be automatically installed and configured by
# munin-node-configure
#
# snmpauto: means the plugin can be automatically installed and configured by
# 'munin-node-configure -snmp'
#
# manual: means the plugin is meant to be manually installed and configured
#
# contrib: means the plugin has been contributed to the Munin project by users
# and may not necessarily conform to all standards
#
# test: means the plugin is used for testing Munin
#
# example: means the plugin is an example
#
# Possible values for 'capabilities' (it is common to see 'autoconf suggest' or
# 'snmpconf'):
#
# autoconf: means that the plugin can be automatically configured via
# 'munin-node-configure'
#
# snmpconf: means that the plugin can be automatically configured via
# 'munin-node-configure -snmp'
#
# suggest: means the plugin is a wildcard plugin and may suggest a list of link
# names that 'munin-node-configure' can make use of
#
# Note that the magic markers affect only the 'munin-node-configure' script,
# and if you never plan to run that script, you don't need to pay any attention
# to magic markers.  Only if you intend for your plugin to be distributed for
# others' use do you necessarily have to think about them.  Still, why not
# write an 'autoconf' test that just returns true or false depending on whether
# your plugin is applicable to the system?

use strict;
use warnings;

$ENV{PATH} =
  join ':',
  qw(
      /sbin
      /bin
      /usr/sbin
      /usr/bin
      /usr/local/sbin
      /usr/local/bin
      /opt/sbin
      /opt/bin
   );

my %HANDLER =
  (
   autoconf => \&handle_autoconf,
   suggest => \&handle_suggest,
   snmpconf => \&handle_snmpconf,
   config => \&handle_config,
  );

##############################################################################
# Subroutines
##############################################################################

sub handle_autoconf() {
  # If you have magic marker 'capabilities=autoconf', add code here that tests
  # whether the plugin can run usefully on the current system.  This should
  # prints 'yes' or 'no (with possible explanation)' depending on whether there
  # is a problem running it, returning an exit value of 0 if yes and 1 if no.

  print "yes\n";
  return 0;
}

sub handle_suggest() {
  # If this is a wildcard plugin, its name should end in '_' and it should have
  # magic marker '#%# capabilities=suggest'.  This routine should print a list
  # of the possible suffixes to appear after that underscore in the symlinks.

  return 1;
}

sub handle_snmpconf() {
  # Print require, index and number lines in the case that this plugin is an
  # SNMP plugin.

  return 1;
}

sub handle_config() {
  # The 'config' parameter just tells the module to list out some metadata
  # about the return values.

  print <<"EOF";
graph_title Title to appear at top of graph
graph_vlabel Graph vertical label (unit)
graph_args --base 1000 --lower-limit 0
graph_category Category
graph_info Some explanatory text about the graph
quantity1.label Brief label for quantity 'quantity1'
quantity1.draw LINE2
quantity1.info More descriptive explanatory text about quantity 'quantity1'
quantity1.warning 60
quantity1.critical 180
EOF
  ;
  exit 0;
}

sub print_data() {
  # Lacking a parameter, find and print the data.

  printf "quantity1.value %f\n", 10.0;
  exit 0;
}

##############################################################################
# Main script
##############################################################################

if($ARGV[0]) {
  if(exists $HANDLER{$ARGV[0]}) {
    exit &{$HANDLER{$ARGV[0]}};
  } else {
    die "Unknown parameter $ARGV[0]\n";
  }
}
print_data;

# vim:syntax=perl
