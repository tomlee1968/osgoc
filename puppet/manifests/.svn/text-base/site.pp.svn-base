# /etc/puppet/manifests/site.pp

###############################################################################
# How this file works
###############################################################################

# In case you want to know, Tom Lee <thomlee@iu.edu> wrote this, and last
# modified it 2015-06-05.

# The purpose of this file, the main "manifest" file for the GOC, is to tell
# the Puppet server how to "classify" each client that connects to it -- that
# is, to define which Puppet "classes" (groups of resource definitions) to
# apply to that client.  Taken together, all the information provided by those
# classes forms that client's "catalog."

# For any given client connecting to the Puppet server and requesting its
# catalog of resources, this file selects which classes of resources are
# appropriate for that client.  It can do so in a number of ways.

# The time-honored way is the "node" object.  This matches the client's
# fully-qualified domain name (FQDN), either directly or via a regular
# expression (or via the special matcher, the "default" bareword, which matches
# anything).  Within the definition of the node object, you call upon classes
# defined elsewhere (usually in modules) that will be applied to the client,
# modifying its catalog.  There may also be some if-then or case conditionals,
# testing facts about the client in order to determine which classes to use.
# You should not, however, directly define any resources in this file, inside
# or outside node definitions.  That is possible to do, but it's not
# recommended.

# Node definitions are probably on their way out, however; it was possible to
# have a node inherit its classes from another node, but this was confusing and
# sometimes ambiguous, and it was deprecated as of Puppet 3.7 and will be
# removed in Puppet 4.0.  You can call upon classes outside of any node object
# definition; these will be added to the catalog no matter what the FQDN is or
# what node definitions match it.  Just as you can within node definitions, you
# can test facts about the client, including its hostname, in order to
# determine which classes to call.

# You can also select classes by means of an external node classifier (ENC).
# This is just a script, which can be written in any scripting language with an
# interpreter installed on this system, that takes the client's FQDN and
# outputs the list of classes that should be applied to that client's catalog.
# The ENC is defined in puppet.conf, not here.  However, even if an ENC has
# populated a client's catalog, Puppet still tries to match a node from this
# file to its FQDN, and any classes found are merged into the catalog.

# You can also select classes with Hiera.  The "hiera_include('classes')"
# statement causes Puppet to go to the Hiera files (beginning with
# /etc/puppet/hiera.yaml, etc., depending on backend) and add classes to the
# client's catalog based on the definition of the "classes" array defined in
# those files.  You could call the array something other than "classes" if you
# prefer, but I recommend that you make it something sensible, and it won't
# work unless the array defined in the Hiera files and the array mentioned by
# the "hiera_include" statement are the same.  That array may be affected by
# different hostnames, distros, major distro versions, or other facts about the
# system.

###############################################################################
# More about node definitions
###############################################################################

# Node definitions may be on their way out; they used to be the only way to do
# this, and they used to be able to inherit classes from other node
# definitions, but there are other ways to classify clients now, and node
# inheritance is now deprecated.  Still, many sites still use them.  A node
# definition looks like this:
#
# node <matcher> {
#   ...
# }
#
# The "name" of a node is its matcher, which Puppet compares with the client's
# FQDN to find out whether the node is the right one to apply to that client's
# catalog.  No two nodes may have the exact same matcher; that will cause a
# catalog compilation error.

# There may be more than one node whose matchers both/all match the client's
# FQDN, however.  In such cases Puppet will use the "most specific" among these
# matchers, and if two nodes are equally "specific," I'm not sure whether it's
# predictable what Puppet will do; be careful not to configure this file that
# way.  Puppet will only ever apply one node definition to a client's catalog.
# Here are the types of matchers you can use, in order from most to least
# "specific":

# * They can be literal FQDNs, like 'dubois.uits.indiana.edu', or a
# comma-separated list of them.  If the client's FQDN matches the string (or
# one of them) exactly, that is considered a match for this node object.  This
# is the most specific possible kind of matcher; if Puppet finds a single
# literal matcher that matches the client, it doesn't look for other matchers.
# Example:
#
# node 'dubois.uits.indiana.edu', 'repo1.grid.iu.edu', 'repo2.grid.iu.edu' {
#   ...
# }

# * (As of Puppet 0.25.0 and later) They can be regular expressions.  These are
# Perl-style regular expressions and must be delimited with forward-slashes.
# If the host's FQDN matches the regular expression, that is considered a match
# for this node object.  This one is not considered very "specific," so Puppet
# will only even look at this matcher if it hasn't matched the client to one of
# the above types of matcher.  If there is more than one node with a regex
# matcher that might match the client, Puppet picks one of them, and there are
# no guarantees about which one it will pick, so try to avoid that.  Example:
#
# node /^web\d+\.grid\.iu\.edu$/ {
#   ...
# }

# * One node can use the bareword "default" (without quotes).  This matcher
# matches everything.  However, this is the least specific possible matcher,
# and Puppet will use it only if nothing else matches.  Example:
#
# node default {
#   ...
# }

# Here is how Puppet determines what node definition to apply to a client's
# catalog, straight from the Puppet 3.0 documentation:
#
# 1. If there is a node definition with the node's exact name, Puppet will use
# it (and stop processing nodes).
#
# 2. If there is a regular expression node statement that matches the node's
# name, Puppet will use it (and stop processing nodes).  (If more than one
# regex node matches, Puppet will use one of them, with no guarantees as to
# which.)

# 3. If it hasn't found a match so far, and if the node's name looks like a
# hostname (multiple segments separated by periods), Puppet will chop off the
# last segment of the name and start over.  'dubois.uits.indiana.edu' will
# become 'dubois.uits.indiana', and we go back to step 1.  This repeats until
# either a match is found or we run out of segments in the name.  If
# 'dubois.uits.indiana' doesn't match anything, Puppet tries 'dubois.uits',
# then 'dubois', then gives up if there's still no match.

# 4. If it still hasn't matched anything, Puppet gets the "default" node and
# applies that to the catalog.

# So, with 'dubois.uits.indiana.edu', Puppet would try the following, in this
# order, jumping out the first time a node definition matched:

# * an exact match for dubois.uits.indiana.edu
# * a regex matching dubois.uits.indiana.edu
# * an exact match for dubois.uits.indiana
# * a regex matching dubois.uits.indiana
# * an exact match for dubois.uits
# * a regex matching dubois.uits
# * an exact match for dubois
# * a regex matching dubois
# * the default node

###############################################################################
# Hiera
###############################################################################

# You will need to do 'yum install hiera' or 'gem install hiera', followed by a
# 'gem install hiera-puppet', to use Hiera.  To use eYAML, do 'gem install
# hiera-eyaml'.  To do deep merging of Hiera arrays and hashes (you probably
# want this), do 'gem install deep_merge'.

# Hiera is a library for loading sequences/arrays/lists and
# mappings/hashes/dictionaries/lookups from a hierarchy of configuration files
# into memory with pluggable backends.  Currently I know that Hiera supports
# YAML and JSON backends, but it may be able to handle others.  Puppet can use
# Hiera in various ways.

# But before Puppet will use Hiera, you have to configure Puppet to use it.
# First you must make a hiera.yaml file (I'm more familiar with YAML than with
# JSON, but I believe you can also make a hiera.json file if you'd rather)
# containing the basic Hiera configuration information.  This file must be in
# the main Puppet configuration directory -- the same one that puppet.conf is
# in.  In it you must define these keys:

# :backends -- a list containing the backends to use.  If you're using YAML,
# 'yaml' would be a good value.  If you're using the encryption extention
# eYAML, add 'eyaml' to the list.

# :hierarchy -- a list of paths to look for files in.  The list should begin
# with the 'defaults' keyword (without quotes), meaning to look in the default
# file locations.  It should end with the 'global' keyword, meaning to look in
# the file "global.yaml" or "global.json" last.  If any files in the list don't
# exist, Hiera doesn't generate any error messages; it just adds data from
# whatever files do exist.  You should put these in order from most specific to
# most general -- files having to do with a particular host should come first,
# followed by files having to do with classes of hosts, with files affecting
# all hosts coming last.  Note that you can use Facter facts in these paths.
# See the example below.

# :yaml -- a hash containing configuration directives for the YAML backend.
# Most important is the ":datadir" directive, stating the top-level directory
# to search for files in.  Any relative paths in the ":hierarchy" list
# (mentioned above) are considered to be relative to this ":datadir" setting.

# :eyaml -- if you are using eYAML ('hiera-eyaml'), there are configuration
# directives here for that.  They include ":datadir" (top-level directory for
# file paths, just like the ":datadir" directive for the ":yaml" configuration
# hash), ":pkcs7_private_key" (path to the private key for encryption),
# ":pkcs7_public_key" (path to the public key), and ":extension" (file
# extension for eYAML files).

# :merge_behavior -- governs what to do when two different Hiera files have
# arrays or hashes with the same name.  It can have three different values:
# 'native', the default, merges only the top-level keys and values; 'deep' is
# apparently useless, according to the Puppet documentation; and 'deeper' is
# probably what you want, as it recursively merges the arrays/hashes all the
# way down, as far as they go.  This setting doesn't affect Hiera values that
# aren't hashes or arrays; they get "priority lookups," which means the first
# value to appear in the ":hierarchy" list is the one that your Puppet rules
# get.  This is why you should put the most specific files first in the
# ":hierarchy" list.

# Example /etc/puppet/hiera.yaml file:

# ---
# :backends:
#   - yaml
#   - eyaml
# :hierarchy:
#   - defaults
#   - "host/%{::hostname}"
#   - "osfamily/%{::osfamily}"
#   - "osfamily/%{::osfamily}/%{::lsbmajdistrelease}"
#   - global
# :yaml:
#   :datadir: "/etc/puppet/env/%{::environment}/hiera"
# :eyaml:
#   :datadir: "/etc/puppet/env/%{::environment}/hiera"
#   :pkcs7_private_key: /etc/puppet/keys/private_key.pkcs7.pem
#   :pkcs7_public_key: /etc/puppet/keys/public_key.pkcs7.pem
#   :extension: "yaml"
# :merge_behavior: deeper

# About the example: As you can see above, facts from Facter can be used in any
# of these values.  The "%{variable}" construction results in the expansion of
# the variable when a node contacts Puppet; the facts used will come from the
# client node.  It is best, according to the documentation, to specify
# "%{::variable}" when referring to these facts, just in case there are somehow
# local variables with the same names; the double-colon notation ensures that
# the top-level variables will be consulted.  Using "%{::environment}" in the
# ":datadir" settings allows you to have environment-specific Hiera files,
# which you probably will want, since you can then make changes to your
# development environment's Hiera files without affecting the testing or
# production environments.  Using "%{::hostname}" in the ":hierarchy" list
# allows you to set up a directory containing Hiera files specific to a certain
# host.

# Next you need to make sure that your ":datadir" exists and put a
# "global.yaml" (or "global.json") file in it.  Any keys/values you place in
# there are available to Hiera for any client node.

# You can have Hiera select which Puppet classes affect which nodes, if you put
# a line saying "hiera_include('classes')" in this file (manifests/site.pp).
# For example, if your global.yaml file contains this code, the "myservices"
# and "mypackages" classes will be used for every client node:

# global.yaml:
# ---
# classes:
#   - mypackages
#   - myservices

# site.pp:
# hiera_include('classes')

# You can achieve the same thing with this line in site.pp instead:
# include(hiera_array('classes', [])

# Once you've used any Hiera function ('hiera', 'hiera_include', 'hiera_array',
# or 'hiera_hash') anywhere in site.pp or any module or class it includes,
# Puppet has loaded the data from Hiera into memory, which means you can now
# refer to any of the keys from Hiera as variables.  If your global.yaml file
# contains this code:

# global.yaml:
# ---
# mymodule::config:
#   thisvalue: enable
#   thatvalue: disable

# then you will be able to refer to the variable $mymodule::config in your
# Puppet code.  It's a hash, so you would probably refer to
# $mymodule::config['thisvalue'], etc.  If other Hiera files assign a value to
# mymodule::config, its keys will be merged with the global ones.

# You can also look up Hiera keys explicitly.  In any .pp file, you can just
# use the Hiera lookup functions.  The 'hiera' function just looks up a scalar
# value:

# $value = hiera('myscalar', 'defaultvalue')

# If the 'myscalar' key doesn't exist anywhere in any of your Hiera files, the
# 'hiera' function will assign it a value of 'defaultvalue'.

# The 'hiera_array' function looks up an array and returns it:

# $array = hiera_array('myarray', [])

# As with the 'hiera' function, the second argument is the default value -- if
# there's no key called 'myarray' anywhere, the $array will just get [] (an
# empty array) as a value.  It's usually good to set a default.  Any values of
# 'myarray' that appear in any of your Hiera files will be merged into one
# array.

# The 'hiera_hash' function looks up a hash and returns it:

# $hash = hiera_hash('myhash', {})

# We've used the default value of {} (an empty hash, in Puppet language).  As
# with arrays, any keys and values of 'myhash' that may appear in any of your
# Hiera files will be merged into one hash, and if none appear, $hash will get
# the default.

# Now, hiera-eyaml is able to encrypt values within Hiera YAML files.  Even if
# the YAML files are publicly readable, even if they're shared to a public
# online repository, those encrypted values will be encrypted, and only someone
# who has a copy of the hiera-eyaml private key (which should be no one) can
# read them (without cracking the encryption).  For hiera-eyaml, you'll need
# to:
#
# 1. Choose a location to put your public and private hiera-eyaml keys in.
# This is a keypair that will be used only to encrypt/decrypt data for
# hiera-eyaml.
#
# 2. Create a keypair using 'eyaml createkeys' (type 'eyaml createkeys --help'
# for more information) and put the keys in the location you came up with in
# the previous step.  Make sure that the Puppet server and whoever will be able
# to edit the hiera-eyaml files will be able to see them, and no one else.

# 3. Configure hiera-eyaml to point to their locations, both in the main Hiera
# config file (so Puppet can find the keys) and in /etc/eyaml/config.yaml (so
# the eyaml command-line utility can find the keys).  An example hiera.yaml
# config file is above.  Here is an example /etc/eyaml/config.yaml:

# /etc/eyaml/config.yaml:
# ---
# pkcs7_private_key: /etc/puppet/keys/private_key.pkcs7.pem
# pkcs7_public_key: /etc/puppet/keys/public_key.pkcs7.pem

# You will now be able to assign encrypted values to Hiera keys.  Set your
# EDITOR environment variable to your preferred text editor and type 'eyaml
# edit <file>.yaml', and you'll see a version of the YAML file you specified
# with a text block at the beginning explaining how to add and modify encrypted
# values.  If there were already encrypted values in the file, you'll see them
# decrypted -- but only because you're using the 'eyaml edit' command.  If you
# exit from the editor and look at the same file some other way, you'll see
# only encrypted data for those values, and that's exactly what anyone else
# will see.  When a client node connects to the Puppet server, hiera-eyaml will
# decrypt those values and send them to the client, so be careful of that --
# but the client-server connection is encrypted, so an attacker won't be able
# to observe the plaintext data in transit.  Someone running Puppet on a remote
# client node may potentially be able to see the plaintext data, though, so be
# careful how you write your Puppet rules and how you allow access to your
# Puppet server.

###############################################################################
# Other miscellaneous information
###############################################################################

# The "include" statement refers to names of classes, not the modules they're
# in (though they are often the same).

# The meanings of the environments are:

# 1. development = machines used for developing Puppet classes/modules (e.g.
# puppet-test, a virtual machine specifically for this purpose)

# 2. testing = machines used for testing Puppet classes/modules (e.g. the ITB
# machines -- do not apply new Puppet rules to them unless they've been tested
# on the development VM)

# 3. production = machines to be careful with and only apply Puppet
# classes/modules to once they've passed the tests (e.g. the production
# machines -- do not apply new Puppet rules to these unless they've been tested
# on ITB machines first)

# How to automatically tell whether the connecting host is an RHEL5 or RHEL6
# box:

# Facter can tell (type "facter" at a root prompt), and its variables are
# automatically imported into Puppet's default namespace.

# On all RHEL-family versions I've encountered so far,
# operatingsystem = "RedHat" for Red Hat, "CentOS" for CentOS, etc.
# osfamily = "RedHat" for Red Hat, CentOS, Fedora, etc.
# and
# operatingsystemrelease = "5.8" for RHEL 5.8, "6.3" for RHEL 6.3, etc.

# Now, if you have the "redhat-lsb" package installed (which I'm trying to
# insist that we do), you get these:
#
# lsbdistcodename = "Tikanga" for RHEL 5.*, "Santiago" for RHEL 6.*, etc.
#
# lsbdistid = "RedHatEnterpriseServer" for any version of RHEL Server
#
# lsbdistrelease = "5.8" for RHEL 5.8, "6.3" for RHEL 6.3, etc.
#
# lsbmajdistrelease = "5" for any RHEL5, "6" for any RHEL6, etc.
#
# and others.

# Global setting for various rules.
$standardpath = [
                  '/sbin',
                  '/bin',
                  '/usr/sbin',
                  '/usr/bin',
                  '/opt/sbin',
                  '/opt/bin',
                  '/usr/local/sbin',
                  '/usr/local/bin',
                  ]

# Define the default path to use for every exec resource
Exec {
  path => [
           '/sbin',
           '/bin',
           '/usr/sbin',
           '/usr/bin',
           '/opt/sbin',
           '/opt/bin',
           '/usr/local/sbin',
           '/usr/local/bin',
           ],
}

# Create a 'first' stage, so we can have classes that process before most
# others.
stage {'first':
  before => Stage['main'],
}

# Prevents a long warning message from appearing on certain clients.
if versioncmp($::puppetversion, '3.6.1') >= 0 {
  $allow_virtual_packages = hiera('allow_virtual_packages', false)
  Package {
    allow_virtual => $allow_virtual_packages,
  }
}

# Temporary rule: install
# http://repo.grid.iu.edu/osg/3.3/el6/development/x86_64/cilogon-ca-certs-1.1-1.osg32.el6.noarch.rpm
# on all but production machines (this might upgrade an earlier
# cilogon-ca-certs RPM)

#class main_temp_cilogon {
#  exec {'main::temp::cilogon':
#    command => "rpm -i http://repo.grid.iu.edu/osg/3.2/el${::lsbmajdistrelease}/release/x86_64/cilogon-osg-ca-cert-1.0-1.osg32.el${::lsbmajdistrelease}.noarch.rpm",
#    unless => "rpm -q --qf '' cilogon-osg-ca-cert",
#  }
#}
#
#if($::environment != 'production') {
#  include main_temp_cilogon
#}

###############################################################################
# Classes to apply to *ALL* hosts
###############################################################################

# include security-test::compromised-ips
include security-test::cleanup-compromised-ips

###############################################################################
# Get classes from Hiera
###############################################################################

# We could just do
#
# hiera_include('classes')
#
# but that doesn't allow us to include a class for all hosts, then
# exclude it for only certain hosts.  This, however, does:

$classes_include = hiera_array('classes', [])
$classes_exclude = hiera_array('classes_exclude', [])
$classes = difference(unique($classes_include), $classes_exclude)
include($classes)

# Print a list of all included classes, if this is puppet-test.grid.iu.edu, so
# we can see what's going on.
if ($hostname == 'puppet-test') {
  $classes_string = join(sort($classes), ", ")
  notify { "Classes: $classes_string": }
}

# Classes not managed by Hiera will have to be included in this
# manifest (currently there are none)

###############################################################################
# Stemcell building
###############################################################################

if $anaconda == 'true' {
  # See hiera/anaconda/true.yaml: this makes sure that this Tidy resource
  # occurs before any Package resources.
  Tidy['centos_repos'] -> Package <| |>

  # This makes sure that this Exec resource occurs after any Package resources.
  Package <| |> -> Exec['yum_clean_all']

  Service{
    ensure => undef,
  }
}

###############################################################################
# Default node
###############################################################################

# Defines the node instance to apply if no more specific node matches
node default {
}
