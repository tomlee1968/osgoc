#!/usr/bin/perl

use strict;
use warnings;

# vmtool -- handle many common VM tasks for GOC VMs
# Tom Lee <thomlee@iu.edu>
# Begun 2009/04/17
# v2.8.32: 2017/11/14

###############################################################################
# Supported Commands
###############################################################################
# This is meant to be called from one of various symlinks:
#
# allvm <virsh or vmware-cmd command>: Do a command for all VMs
# autovm <vm_name>: Set a VM to autostart when host boots
# buildvm <vm_name>: Build a VM from PXE boot/Cobbler/Anaconda
# cpvm <vm_name> <vm_newname>: Copy a VM's parameters to a new VM
# exportvm <vm_name>: Exports a VM as a tarball
# importvm <vm_name>: Imports a VM from a tarball created by exportvm
# lsvm: List all VMs on system
# merge_all_snapshots: Merge all of a VM's snapshots.
# mkvm <vm_name>: Create a new VM
# mvvm <vm_name> <vm_newname>: Rename a VM (the VM cannot be running)
# noautovm <vm_name>: Set a VM to not autostart when host boots
# rebuild_stemcell: Rebuilds a stemcell and uploads it to NFS
# rebuild_vmware: Rebuilds VMware Server's modules
# rmvm <vm_name>: Delete a VM (the VM cannot be running)
# swapvm <first_vm> <second_vm>: Switches two VMs' identities
# vmdown <vm_name>: Shut down a VM
# vmup <vm_name>: Start a VM
#
# where VM names can only contain letters, numbers, and the characters ._+-

###############################################################################
# About the config file
###############################################################################
# The /opt/etc/vmtool.conf file sets the following:
#
# VM_DIR: The full path to the directory containing all VM volumes' mount
# points/directories (usually /vm)
#
# VM_VG: The volume group containing all VM LVs (or containing the /vm LV)
#
# VM_TAG: The LVM tag to give all VM LVs (if they have separate LVs)
#
# USR_LOCAL_SIZE: The default size for /usr/local on VMs; this is given as a
# number and a unit (e.g. "32GiB").  See below for more about units.
#
# VM_SOURCE: The path to the source VM, which will be used as a starting point
# when a new VM is created

###############################################################################
# GOC standards for VMs:
###############################################################################
# Old-style VMware:
#
# 1. There must be a LV on VG $VM_VG (see /opt/etc/vmtool.conf) named <vm_name>
# with tag "vm" (use "--addtag vm" when doing lvcreate)
#
# 2. The filesystem label on that LV's filesystem must be $VM_DIR/<vm_name>
# (use "-L <label>" when doing mkfs)
#
# 3. There must be a mount point at $VM_DIR/<vm_name> for the volume
#
# 4. There must be a line in /etc/fstab to mount that mounts the volume by
# label (LABEL=$VM_DIR/<vm_name> $VM_DIR/<vm_name> default 0 0)
#
# 5. There must be a $VM_DIR/<vm_name>/<vm_name>.vmx
#
# 6. The .vmx file must contain a line: displayname = "<vm_name>"
#
# Upon further reflection, I don't really know why we started using a separate
# LV for each VM.  There's no real reason why we couldn't have an LV for all
# VMs, giving each VM a directory within that LV.  That would eliminate steps
# 1-4 above, making things MUCH simpler.  Perhaps we'll move toward this in the
# future.
#
# New-style ("flat") VMware:
#
# 1. There must be a mounted volume on $VM_DIR (usually /vm)
#
# 2. There must be a $VM_DIR/<vm_name>/<vm_name>.vmx
#
# 3. The .vmx file must contain a line: displayname = "<vm_name>"
#
# KVM:
#
# 1. There must be a $VM_DIR (usually /var/lib/libvirt/images)
#
# 2. The VM must be consistent with virsh
#
###############################################################################
# Units
###############################################################################

# I've written an auxiliary module called DataAmount.pm that parses quantities
# of data given to it and stores them internally as a raw number of bytes, with
# methods capable of expressing the number in a variety of units.  See that
# file for how it works internally.  Here, however, I should still document
# what units we accept.

# When dealing with hard drive sizes, manufacturers usually measure in
# powers-of-10 units -- they will say "500 GB," by which they mean what we're
# calling "500gb" in this script.  In other words, 500 x 10^9 bytes.  However,
# when dealing with amounts of memory and sizes of files, manufacturers and
# programmers tend to measure in powers-of-2 units -- if they say "32 GB" or
# "32 gigabytes," what they really mean is "32 gibibytes," which we'd call
# "32gib" in this script -- in other terms, 32 x 2^30 bytes.  It's important to
# know exactly how much data we're dealing with, so this script differentiates.

# This script accepts IEEE1541 units, which are the international standard:
#
# kB (kilobyte)  =                     1,000 bytes = 10^3 bytes
# MB (megabyte)  =                 1,000,000 bytes = 10^6 bytes  = 1000 kB
# GB (gigabyte)  =             1,000,000,000 bytes = 10^9 bytes  = 1000 MB
# TB (terabyte)  =         1,000,000,000,000 bytes = 10^12 bytes = 1000 GB
# PB (petabyte)  =     1,000,000,000,000,000 bytes = 10^15 bytes = 1000 TB
# EB (exabyte)   = 1,000,000,000,000,000,000 bytes = 10^18 bytes = 1000 PB
# kiB (kibibyte) =                     1,024 bytes = 2^10 bytes
# MiB (mebibyte) =                 1,048,576 bytes = 2^20 bytes = 1024 kiB
# GiB (gibibyte) =             1,073,741,824 bytes = 2^30 bytes = 1024 MiB
# TiB (tebibyte) =         1,099,511,627,776 bytes = 2^40 bytes = 1024 GiB
# PiB (pebibyte) =     1,125,899,906,842,624 bytes = 2^50 bytes = 1024 TiB
# EiB (exbibyte) = 1,152,921,504,606,846,976 bytes = 2^60 bytes = 1024 PiB
#
# It actually accepts these case-insensitively, because there's no ambiguity
# between MB and mb.
#
# It also accepts single-character "LVM units," so called because the Logical
# Volume Manager uses them, and several other software packages use the same
# convention:
#
# k = kB	K = kiB
# m = MB	M = MiB
# g = GB	G = GiB
# t = TB	T = TiB
# p = PB	P = PiB
# e = EB	E = EiB
#
# "LVM units" are case-sensitive, obviously.
#
# NOTE that qemu-img uses units that looks like "LVM units" but aren't -- to
# qemu-img, 1k = 1K = 1kiB, 1M = 1MiB, 1G = 1GiB, etc., and '1m' and '1g' cause
# syntax errors.  This script does not accept quantities expressed in "qemu-img
# units," though it translates things into qemu-img's terms when it has to.
#
# Yes, the script supports ZB (10^21), YB (10^24), ZiB (2^70), and YiB (2^80),
# even though it's unlikely that those will appear in actual use anytime soon.

###############################################################################
# Modules
###############################################################################

use lib '/usr/share/perl5';
use Carp;
use Crypt::Random qw(makerandom);
use Cwd qw(cwd realpath);
use DataAmount;
use File::Basename;
use File::Copy;
use File::Temp;
use Getopt::Std;
use IO::Dir qw(DIR_UNLINK);
use IO::File;
use IPC::Open3;
use Math::BigInt;
use NetAddr::IP qw(:lower);
use Net::Ping;
use OSSP::uuid;
use POSIX;
use Socket;
use Socket6;
use Socket::GetAddrInfo qw(:newapi getaddrinfo getnameinfo);
use Symbol qw(gensym);
use Sys::Guestfs;
use Sys::Hostname;
use Sys::Virt;
use Try::Tiny;
use XML::Twig;

###############################################################################
# Settings
###############################################################################

# Version number
$main::VERSION = '2.8.32';

# Verbose carp and croak
$Carp::Verbose = 1;

# Set the path
$ENV{PATH} = join(':', qw(/sbin /bin /usr/sbin /usr/bin /opt/sbin /opt/bin));

# This is the approximate size of all the files in the VM other than the
# /usr/local virtual disk.  If there's a significant change to the VM, change
# this.  This should be in 'gib'.
$CFG::BASE_VM_SIZE = DataAmount->new('64gib');

# Config file -- all config variables are in namespace $CFG::
$CFG::CONFIG = '/opt/etc/vmtool.config';

# Name of mkvm config file in SVN install tree -- this is only used by mkvm,
# and the script will read install/common/$CFG::MKVM_CONFIG, then
# install/$SERVICE/$CFG::MKVM_CONFIG, in that order.  If either file doesn't
# exist, no errors will appear; there just won't be any configuration changes.
$CFG::MKVM_CONFIG = 'mkvm.config';

# How the script was called
$CFG::CALLED_AS = basename($0);

# Is this a VMWare Server or qemu/kvm system?
if(-e '/usr/bin/vmware') {
  $CFG::KVM = '';
  $CFG::VM_DIR = '/vm';
} else {
  $CFG::KVM = 1;
  $CFG::VM_DIR = '/var/lib/libvirt/images';
}

# Name of stemcell
$CFG::STEMCELL = 'stemcell';

# Where to find (for mkvm) and put (for rebuild_stemcell) the stemcell tarball
$CFG::ARCHIVE_DIR = '/net/cobbler.goc/usr/local/cobbler/pub';

# Whether we should start the VM or not after creating it, renaming it,
# exporting it, and other operations that begin with the VM not being powered
# on.
$CFG::START = '';

# How many backup stemcells to keep
$CFG::NBAK = 3;

# Default distro (for selecting stemcell image)
# 5 = RHEL 5
# 6 = RHEL 6
# c6 = CentOS 6
# c7 = CentOS 7
# other codes may be defined later
$CFG::DISTRO = '6';

# Default architecture ('x86' or 'x86_64')
$CFG::ARCH = 'x86_64';

# Volume group containing all VM LVs (if using old non-flat LVM)
$CFG::VM_VG = 'vg0';

# LVM tag to give all VM LVs (if using old non-flat LVM)
$CFG::VM_TAG = 'vm';

# Whether to use the X11 console (by default) when doing rebuild_stemcell
$CFG::X11 = '';

###############################################################################
# Data
###############################################################################

# Here is the list of commands and the routines that support them.
# allvm: run a vmware-cmd or virsh command on all VMs
# autovm: set a VM to autostart
# buildvm: make a VM, boot from PXE, and build with Anaconda
# exportvm: export a VM's files as a tarball for importvm to read
# importvm: import a VM from a tarball that exportvm has created
# lsvm: list all VMs on host
# merge_all_snapshots: merge all of a VM's snapshots
# mkvm: create a VM from stemcell image created by rebuild_stemcell
# mvvm: rename a VM
# noautovm: set a VM to NOT autostart
# rebuild_stemcell: uses PXE boot and Anaconda to rebuild stemcell image
# rebuild_vmware: recompiles VMware modules (e.g. after kernel update)
# rmvm: delete a VM
# swapvm: switch two VMs' identities
# vmdown: take a VM down and wait for it to be down
# vmup: bring a VM up and wait for it to be up

%main::ROUTINES =
  (
   allvm => \&do_allvm,
   autovm => \&do_autovm,
   buildvm => \&do_buildvm,
   cpvm => \&do_cpvm,
   exportvm => \&do_exportvm,
   importvm => \&do_importvm,
   lsvm => \&do_lsvm,
   merge_all_snapshots => \&do_merge_all_snapshots,
   mkvm => \&do_mkvm,
   mvvm => \&do_mvvm,
   noautovm => \&do_autovm,
   rebuild_stemcell => \&do_rebuild_stemcell,
   rebuild_vmware => \&do_rebuild_vmware,
   rmvm => \&do_rmvm,
   swapvm => \&do_swapvm,
   vmdown => \&do_stop,
   vmup => \&do_start,
  );

# This maps distro codes (used in the -r command-line option to mkvm and
# rebuild_stemcell) to their names for human readability.  If we add more
# distros, add entries for them here.

%main::DISTRONAME =
  (
   5 => 'RHEL 5',
   6 => 'RHEL 6',
   c6 => 'CentOS 6',
   c7 => 'CentOS 7',
   '' => 'unknown',
  );

# Data about GOC VLANs.
%main::VLANDATA =
  (
   'public' =>
   {
    site => 'iub',
    id => '259',
    label => 'public',
    intf => 'eth0',
    prefix =>
    {
     ipv4 => NetAddr::IP->new('129.79.53.0/24'),
     ipv6 => NetAddr::IP->new('2001:18e8:2:6::/64'),
    },
    gateway =>
    {
     ipv4 => '129.79.53.1',
     ipv6 => '2001:18e8:2:6::1',
    },
   },
   'private' =>
   {
    site => 'iub',
    id => '4020',
    label => 'private',
    intf => 'eth1',
    prefix =>
    {
     ipv4 => NetAddr::IP->new('192.168.96.0/22'),
     ipv6 => NetAddr::IP->new('fd2f:6feb:37::/48'),
    },
   },
  );

###############################################################################
# Subroutines
###############################################################################

sub debug_printf($@) {
  # For printing things in debug mode.  Given a format and a list of data
  # items, print to standard output with a debug mode prefix and a built-in
  # newline -- but only if $CFG::DEBUG_MODE is true.  If it isn't, print
  # nothing.
  my($fmt, @data) = @_;
  printf '*** DEBUG: '.$fmt."\n", @data if $CFG::DEBUG_MODE;
}

sub test_printf($@) {
  # For printing things in test mode.  Given a format and a list of data items,
  # print to standard output with a test mode prefix and a built-in newline.
  my($fmt, @data) = @_;
  printf '(test mode) '.$fmt."\n", @data;
}

sub test_cmd() {
  # If $CFG::TEST_MODE is true, prints the given shell command line.
  # Otherwise, executes it.  Returns the command's return code.  In test mode,
  # always returns 0.

  # A command long enough to be broken up into multiple lines for readability
  # can be sent as an array of strings, which this function will join together,
  # or with carriage returns, which this function will replace with spaces.

  my(@cmd) = @_;
  my $cmd = join(' ', @cmd);
  $cmd =~ s/\n/ /gm;
  if($CFG::TEST_MODE) {
    test_printf '%s', $cmd;
    return(0);
  }
  return(system($cmd) >> 8);
}

sub read_config() {
  # Read the given config file, if it exists.  Returns '' on success and an
  # error string if there was a problem.

  my($file) = @_;

  return("$file does not exist") unless (-e $file);
  return("Unable to read $file: Insufficient permission") unless (-r $file);
  our $err = '';
  {
    package CFG;
    my $return = do($file);
    if($@) {
      $::err = "Unable to compile $file: $@";
    } elsif(!defined($return)) {
      $::err = "Unable to read $file: $!";
    } elsif(!$return) {
      $::err = "Unable to process $file";
    }
  }
  return($err);
}

sub read_mkvm_service_config() {
  # If this is a 'mkvm', try to figure out what service this is, and look in
  # SVN for the common and service-specific config parameters.  These are the
  # same ones that are available in $CFG::CONFIG, but they're customized for
  # mkvm in general (in the 'common' directory of the install tree) and the
  # service specifically (in the service's directory in the install tree).

  # (Currently doesn't work because the SVN server has been taken down and we
  # aren't set up to use git yet -- TJL 2015-03-18)

  # Go through @ARGV to find the VM name.

  my $vm_name = '';
  # If the Last Arg Required a Parameter, this will be true:
  my $larp = '';
  foreach my $arg (@ARGV) {
    # If the Last Arg Required a Parameter, then this arg is the parameter to
    # the last arg and is not of interest to us.  Turn $larp off and skip it.
    if($larp) {
      $larp = '';
      next;
    }
    # If this arg starts with '-', it's a switch.  See if it's one of the ones
    # that requires a parameter.
    if(substr($arg, 0, 1) eq '-') {
      if($arg =~ /^-[cfmrs]$/) {
	# This switch requires a parameter.  Presumably the next arg is that
	# parameter.  Set $larp so we'll know that the Last Arg Required a
	# Parameter.
	$larp = 1;
      }
      # We're not interested in this arg anymore.  Skip to the next.
      next;
    }
    # We've found an arg that doesn't start with '-' and doesn't follow a '-'
    # switch that requires a parameter.  Must be the VM name.
    $vm_name = $arg;
    last;
  }

  # Make a temp directory for checking out SVN files into.
  my $tempdir = File::Temp::tempdir('mkvm.XXXXXXXX', DIR => $CFG::VM_DIR, CLEANUP => 1);

  # Attempt to check out and read the common config file.
  if((system("svn -q --depth=files --non-interactive --trust-server-cert co https://osg-svn.rtinfo.indiana.edu/goc-internal/install/common $tempdir/common") >> 8) != 0) {
    carp "Unable to check out SVN install/common directory.";
    return '';
  }
  &read_config("$tempdir/common/$CFG::MKVM_CONFIG");


  # Attempt to check out and read the service-specific config file.
  unless($vm_name) {
    carp "Unable to determine VM name, so can't read service-specific mkvm config.";
    return '';
  }

  my($service) = split(/\./, $vm_name, 2);
  $service = &determine_service($service);
  if((system("svn -q --depth=files --non-interactive --trust-server-cert co https://osg-svn.rtinfo.indiana.edu/goc-internal/install/$service $tempdir/$service") >> 8) != 0) {
    carp "Unable to check out SVN install/$service directory.";
    return '';
  }
  &read_config("$tempdir/$service/$CFG::MKVM_CONFIG");
}

sub make_main_dataamounts() {
  # Make sure the main DataAmount globals ($CFG::MEM_SIZE,
  # $CFG::USR_LOCAL_SIZE, and $CFG::BASE_VM_SIZE) are DataAmounts.  Exit the
  # entire script with an error if they're illegible, or if they're some other
  # object somehow.

  unless(ref($CFG::BASE_VM_SIZE) eq 'DataAmount') {
    croak "ref(\$CFG::BASE_VM_SIZE) == ".ref($CFG::BASE_VM_SIZE).", and that shouldn't happen" if ref($CFG::BASE_VM_SIZE);
    $CFG::BASE_VM_SIZE = DataAmount->new($CFG::BASE_VM_SIZE);
    croak "Illegible base VM size '$CFG::BASE_VM_SIZE'" unless($CFG::BASE_VM_SIZE->bytes());
  }
  unless(ref($CFG::USR_LOCAL_SIZE) eq 'DataAmount') {
    croak "ref(\$CFG::USR_LOCAL_SIZE) == ".ref($CFG::USR_LOCAL_SIZE).", and that shouldn't happen" if ref($CFG::USR_LOCAL_SIZE);
    $CFG::USR_LOCAL_SIZE = DataAmount->new($CFG::USR_LOCAL_SIZE);
    croak "Illegible /usr/local size '$CFG::USR_LOCAL_SIZE'" unless($CFG::USR_LOCAL_SIZE->bytes());
  }
  unless(ref($CFG::MEM_SIZE) eq 'DataAmount') {
    croak "ref(\$CFG::MEM_SIZE) == ".ref($CFG::MEM_SIZE).", and that shouldn't happen" if ref($CFG::MEM_SIZE);
    $CFG::MEM_SIZE = DataAmount->new($CFG::MEM_SIZE);
    croak "Illegible memory size '$CFG::MEM_SIZE'" unless($CFG::MEM_SIZE->bytes());
  }
}

sub init() {
  # Do initialization stuff.

  $CFG::VM_HOST_TYPE = &vm_host_type();
  &read_config($CFG::CONFIG);
  # If this is mkvm, see if there are any config parameters in SVN specific to
  # the service suggested by the VM name.  However, if the '-v' or '-h' options
  # are present (to just print the version number and/or help text and then
  # exit), there's no need for that.
#  if(($CFG::CALLED_AS eq 'mkvm') && ! grep { $_ eq '-v' || $_ eq '-h' } @ARGV) {
#    &read_mkvm_service_config();
#  }
  &make_main_dataamounts();
  &get_options();
  # Call this again because the options might have changed the variables.
  &make_main_dataamounts();
  if(($ENV{USER} eq 'root') && (substr($CFG::VM_HOST_TYPE, 0, 2) eq 'vm')) {
    &fix_vmware_perl_api_errors();
  }
  if($CFG::VM_HOST_TYPE eq 'kvm') {
    # Make a Sys::Virt object because we'll need it
    if($CFG::CALLED_AS eq 'lsvm') {
      $CFG::VMM = Sys::Virt->new
	(
	 uri => 'qemu:///system',
	 readonly => 1,
	);
    } else {
      $CFG::VMM = Sys::Virt->new
	(
	 uri => 'qemu:///system',
	);
    }
  }
  debug_printf "I've been called as %s", $CFG::CALLED_AS;
}

sub main::HELP_MESSAGE() {
  # Print a help message, based on the command in $CFG::CALLED_AS.
  my $memsize = $CFG::MEM_SIZE->in_min_base2_unit();
  my $usr_local_size = $CFG::USR_LOCAL_SIZE->in_min_base10_unit();
  my $std = <<"EOF";
  -d: Debug mode: prints extra debugging output
  -h: Print this help message
  -t: Test mode: prints shell commands instead of executing
  -v: Print the version
EOF
  ;
  if($CFG::CALLED_AS eq 'allvm') {
    if($CFG::KVM) {
      print("Usage: allvm <domain command from virsh>\n");
      system("virsh help domain");
    } else {
      print("Usage: allvm <command from vmware-cmd>\n");
      system("vmware-cmd --list");
    }
  } elsif($CFG::CALLED_AS eq 'autovm' or $CFG::CALLED_AS eq 'noautovm') {
    print <<"EOF";
Usage: ${CFG::CALLED_AS} [<options>] <name of VM>
Options:
$std
EOF
    ;
  } elsif($CFG::CALLED_AS eq 'buildvm') {
    print <<"EOF";
Usage: ${CFG::CALLED_AS} [<options>] <name of new VM>
Options:
$std
  -3: Choose 32-bit (i386) system (works only with RHEL 5)
  -a: Set the new VM to NOT power on when host boots (default=autostart)
  -c: Set the number of virtual CPUs (1 or 2, default=$CFG::NUMVCPUS)
  -i: Autorun the install script on boot, if possible (default = don't)
  -m: Memory size of new VM (default=$memsize)
  -n: Does nothing (for backward compatibility)
  -p: Start up the new VM after creating (default=don't)
  -r: Choose distro to install (default=$CFG::DISTRO, for $main::DISTRONAME{$CFG::DISTRO})
  -s <size>: Size of /usr/local on new VM (default=$usr_local_size)
  -u: Do not set up the VM's network parameters on boot (default = do this)

  Size specification for -m and -s: <number>[<unit>]
  Both SI (GB/GiB) and "LVM" units (g/G) are acceptable.
  Units: (most common for -s)      (most common for -m)
            k = KB = 1000            K = KiB = 1024
            m = MB = 1000^2          M = MiB = 1024^2
            g = GB = 1000^3          G = GiB = 1024^3
            t = TB = 1000^4          T = TiB = 1024^4
            etc. (default = MiB)
EOF
;
  } elsif($CFG::CALLED_AS eq 'cpvm') {
    print <<"EOF";
Usage: ${CFG::CALLED_AS} [<options>] <name of original VM> <name of new VM>
Creates a new VM with the given original VM's specs -- like using mkvm with the
same -a, -c, -m, and -s parameters, only you don't have to look them up.
Options:
$std

  -c: With this option, also make a copy of the original's virtual disks.
      NOTE: If you choose -c, and if the original VM is running, this command
      will shut it down before the copy and bring it back up afterward.
  -p: Start up the new VM after copying (default = don't).
  -r <distro>: Set distro of new VM that will be written in the config file
      (currently this has no effect), since there's no way to determine that
      from here (default=$CFG::DISTRO, for $main::DISTRONAME{$CFG::DISTRO}).
EOF
;
  } elsif($CFG::CALLED_AS eq 'exportvm') {
    print <<"EOF";
Usage: ${CFG::CALLED_AS} [<options>] <name of VM>
Options:
$std
  -c: Don't convert split disks to monolithic (VMware only) (default: convert)
  -f <path>: Path of file to export to (default derived from VM name)
  -s: Don't merge snapshots before export (VMware only) (default: merge them)

  NOTE that using -c and/or -s will usually result in an export tarball that
  won't be importable into KVM (but can be imported onto another VMware host).

  NOTE ALSO that if the VM is running, this command will shut it down before
  the export and bring it back up afterward.
EOF
;
  } elsif($CFG::CALLED_AS eq 'importvm') {
    print <<"EOF";
Usage: ${CFG::CALLED_AS} [<options>] <tarball to import>
Options:
$std
  -n <name of VM>: Name of VM to create (default taken from tarball)
  -p: Power on the VM after importing
EOF
;
  } elsif($CFG::CALLED_AS eq 'lsvm') {
    print <<"EOF"
Usage: ${CFG::CALLED_AS} [<options>]
Options:
$std
  -a: Add a column about whether each VM is set to autostart
  -c: Print output in HTML format with CSS styles (for vmlist)
  -n: Don't print column headers (-c doesn't print them anyway)
  -r: Add columns for resources: RAM, CPUs, disk space
  -s: Add a column about how many snapshots each VM has

Notes about meanings of resources (not visible unless -r specified):

The CPU and RAM columns reports the number of virtual CPUs and RAM each VM has
been allocated.

Virtual disk image files are often sparse files, meaning that their allocated
size differs from the total size of the blocks they're actually using. This
utility reports both. "Disk (Used)" is the total amount of disk space currently
being used by each VM's disk image files, but they can't use more than the
amount shown in "Disk (Max)".

Notes about the resource totals at the bottom of the table:

The "DEFINED" totals are the sum of the resources used by all VMs defined on
the host, whether they are online or not, while the "ONLINE" totals are only
for VMs that are online. Offline VMs don't use RAM or CPU, but they do still
use disk space.

The "HOST" line reports the host's number of physical CPUs, amount of physical
RAM, and disk space on the volume where the virtual disk images are stored.

If PERCENT ONLINE (CPUs) reaches 100%, VM performance may be degraded.

If PERCENT ONLINE (RAM) reaches 100%, VM performance will be significantly
degraded.

If PERCENT ONLINE (Disk(Max)) reaches 100%, it becomes possible for the VMs to
cause the volume to fill up, which will probably take all the host's VMs
offline. This will happen before PERCENT DEFINED (Disk(Used)) reaches 100%.

EOF
      ;
  } elsif($CFG::CALLED_AS eq 'merge_all_snapshots') {
    print <<"EOF"
Usage: ${CFG::CALLED_AS} [<options>]
Options:
$std
EOF
      ;
  } elsif($CFG::CALLED_AS eq 'mkvm') {
    print <<"EOF";
Usage: ${CFG::CALLED_AS} [<options>] <name of new VM>
Options:
$std
  -1: Run Puppet on first boot (default=don't)
  -3: Choose 32-bit variant (only works for RHEL 5)
  -a: Set the new VM to NOT power on when host boots (default=autostart)
  -c <cpus>: Set the number of virtual CPUs (1 or 2, default=$CFG::NUMVCPUS)
  -f <file>: Specify path to non-default stemcell file to use
  -e <env>: Puppet environment (development, testing, production)
  -i: Autorun the install script on boot, if possible (default = don't)
  -m <mem>: Memory size of new VM (default=$memsize)
  -n: Does nothing (for backward compatibility)
  -p: Power on the new VM after creating (default=don't)
  -r <distro>: Choose distro to install (default=$CFG::DISTRO, for $main::DISTRONAME{$CFG::DISTRO})
  -s <size>: Size of /usr/local on new VM (default=$usr_local_size)
  -u: Do not set up the VM's network parameters on boot (default = do this)
  -y: Answer yes to all questions

  Size specification for -m and -s: <number>[<unit>]
  Both SI (GB/GiB) and "LVM" units (g/G) are acceptable.
  Units: (most common for -s)      (most common for -m)
            k = KB = 1000            K = KiB = 1024
            m = MB = 1000^2          M = MiB = 1024^2
            g = GB = 1000^3          G = GiB = 1024^3
            t = TB = 1000^4          T = TiB = 1024^4
            etc. (default = MiB)
EOF
;
  } elsif($CFG::CALLED_AS eq 'mvvm') {
    print <<"EOF"
Usage: mvvm <VM's old name> <VM's new name>
Options:
$std
  -c: "Complete" rename -- change hostname, networking parameters

  NOTE: If the VM is running, this command will shut it down before renaming it
  and bring it back up afterwards.
EOF
      ;
  } elsif($CFG::CALLED_AS eq 'rebuild_stemcell') {
    print <<"EOF";
Usage: rebuild_stemcell [<options>]
Options:
$std
  -3: Specify 32-bit (RHEL 5 only)
  -f <file>: Specify a directory path or filename to create
  -r <distro>: Choose distro to rebuild (default=$CFG::DISTRO, for $main::DISTRONAME{$CFG::DISTRO})
  -x: Show console via X11 (default=don't)

  Size specification for -m and -s: <number>[<unit>]
  Both SI (GB/GiB) and "LVM" units (g/G) are acceptable.
  Units: (most common for -s)      (most common for -m)
            k = KB = 1000            K = KiB = 1024
            m = MB = 1000^2          M = MiB = 1024^2
            g = GB = 1000^3          G = GiB = 1024^3
            t = TB = 1000^4          T = TiB = 1024^4
            etc. (default = MiB)
EOF
    ;
  } elsif($CFG::CALLED_AS eq 'rmvm') {
    print <<"EOF"
Usage: rmvm <name of VM to delete>
Options:
$std
  -y: Answer yes to all questions
  NOTE: If the VM is running, this command will shut it down before deleting
  it.
EOF
      ;
  } elsif($CFG::CALLED_AS eq 'swapvm') {
    print <<"EOF";
Usage: swapvm [<options>] <first_vm> <second_vm>
Options:
$std
  -c: "Complete" swap -- change the VMs' network identities (without this, only
      the names will be changed)

  NOTE: If either of the VMs is running, this command will shut it down before
  swapping them and bring it back up afterwards.
EOF
    ;
  } elsif(($CFG::CALLED_AS eq 'vmup')
	  || ($CFG::CALLED_AS eq 'vmdown')) {
    print <<"EOF"
Usage: $CFG::CALLED_AS <name of VM>
Options:
$std
EOF
      ;
  }
}

sub main::VERSION_MESSAGE() {
  # Print the version.

  print <<"EOF";
$CFG::CALLED_AS version $main::VERSION
EOF
  ;
}

sub get_options() {
  # Deal with command-line options.

  # Options available for all commands
  my $optstring = 'dhtv';
  $Getopt::Std::STANDARD_HELP_VERSION = 1;
  %CFG::OPTS = ();
  # Some commands have additional options
  if($CFG::CALLED_AS eq 'buildvm') {
    $optstring .= '3ac:im:npr:s:u';
  } elsif($CFG::CALLED_AS eq 'cpvm') {
    $optstring .= 'cpr:';
  } elsif($CFG::CALLED_AS eq 'exportvm') {
    $optstring .= 'cf:s';
  } elsif($CFG::CALLED_AS eq 'importvm') {
    $optstring .= 'n:p';
  } elsif($CFG::CALLED_AS eq 'lsvm') {
    $optstring .= 'acnrs';
  } elsif($CFG::CALLED_AS eq 'mkvm') {
    $optstring .= '13ac:e:f:im:npr:s:uy';
  } elsif($CFG::CALLED_AS eq 'mvvm') {
    $optstring .= 'c';
  } elsif($CFG::CALLED_AS eq 'rebuild_stemcell') {
    $optstring .= '3f:r:x';
  } elsif($CFG::CALLED_AS eq 'rmvm') {
    $optstring .= 'y';
  } elsif($CFG::CALLED_AS eq 'swapvm') {
    $optstring .= 'c';
  }
  # Get the options
  &getopts($optstring, \%CFG::OPTS);
  # Process the options -- depends on command
  if($CFG::CALLED_AS eq 'buildvm') {
    if($CFG::OPTS{3}) {
      $CFG::ARCH = 'x86';
    }
    if($CFG::OPTS{a}) {
      $CFG::NOAUTOSTART = 1;
    }
    if($CFG::OPTS{c}) {
      unless($CFG::KVM) {
	if(($CFG::OPTS{c} != 1) && ($CFG::OPTS{c} != 2)) {
	  die "Valid values for the -c option are 1 and 2.\n";
	}
      }
      $CFG::NUMVCPUS = $CFG::OPTS{c};
    }
    if($CFG::OPTS{i}) {
      $CFG::AUTOINSTALL = 1;
    }
    if($CFG::OPTS{m}) {
      $CFG::MEM_SIZE = DataAmount->new($CFG::OPTS{m});
      die "Illegible memory size '$CFG::OPTS{m}'\n" unless defined($CFG::MEM_SIZE->bytes());
    }
    if($CFG::OPTS{p}) {
      $CFG::START = 1;
    }
    if($CFG::OPTS{r}) {
      unless(grep { $CFG::OPTS{r} eq $_ } grep { $_ } keys %main::DISTRONAME) {
	die (sprintf "Valid values for the -r option: %s\n",
	     (join ' ', grep { $_ } sort keys %main::DISTRONAME));
      }
      $CFG::DISTRO = $CFG::OPTS{r};
    }
    if($CFG::OPTS{s}) {
      $CFG::USR_LOCAL_SIZE = DataAmount->new($CFG::OPTS{s});
      die "Illegible /usr/local size '$CFG::OPTS{s}'\n" unless defined($CFG::USR_LOCAL_SIZE->bytes());
    }
    if($CFG::OPTS{u}) {
      $CFG::NOAUTONET = 1;
    }
  } elsif($CFG::CALLED_AS eq 'cpvm') {
    if($CFG::OPTS{c}) {
      $CFG::CPVM_COPY_DISKS = 1;
    }
    if($CFG::OPTS{p}) {
      $CFG::START = 1;
    }
    if($CFG::OPTS{r}) {
      unless(grep { $CFG::OPTS{r} eq $_ } grep { $_ } keys %main::DISTRONAME) {
	die (sprintf "Valid values for the -r option: %s\n",
	     (join ' ', grep { $_ } sort keys %main::DISTRONAME));
      }
      $CFG::DISTRO = $CFG::OPTS{r};
    }
  } elsif($CFG::CALLED_AS eq 'exportvm') {
    if($CFG::OPTS{c}) {
      $CFG::NO_DISK_CONVERT = 1;
    }
    if($CFG::OPTS{f}) {
      $CFG::EXPORT_FILENAME = $CFG::OPTS{f};
    }
    if($CFG::OPTS{s}) {
      $CFG::NO_SNAPSHOT_MERGE = 1;
    }
  } elsif($CFG::CALLED_AS eq 'importvm') {
    if($CFG::OPTS{n}) {
      $CFG::IMPORT_NAME = $CFG::OPTS{n};
    }
    if($CFG::OPTS{p}) {
      $CFG::START = 1;
    }
  } elsif($CFG::CALLED_AS eq 'lsvm') {
    if($CFG::OPTS{a}) {
      $CFG::LSVM_AUTO = 1;
    }
    if($CFG::OPTS{c}) {
      $CFG::LSVM_CSS = 1;
    }
    if($CFG::OPTS{n}) {
      $CFG::LSVM_NOHDR = 1;
    }
    if($CFG::OPTS{r}) {
      $CFG::LSVM_RES = 1;
    }
    if($CFG::OPTS{s}) {
      $CFG::LSVM_SS = 1;
    }
  } elsif($CFG::CALLED_AS eq 'mkvm') {
    if($CFG::OPTS{1}) {
      $CFG::PUPPET_FIRSTBOOT = 1;
    }
    if($CFG::OPTS{3}) {
      $CFG::ARCH = 'x86';
    }
    if($CFG::OPTS{a}) {
      $CFG::NOAUTOSTART = 1;
    }
    if($CFG::OPTS{c}) {
      unless($CFG::KVM) {
	if(($CFG::OPTS{c} != 1) && ($CFG::OPTS{c} != 2)) {
	  die "Valid values for the -c option are 1 and 2.\n";
	}
      }
      $CFG::NUMVCPUS = $CFG::OPTS{c};
    }
    if($CFG::OPTS{e}) {
      unless($CFG::OPTS{e} eq 'development' or $CFG::OPTS{e} eq 'testing' or $CFG::OPTS{e} eq 'production') {
	die "Valid values for the -e- option are 'development', 'testing', and 'production'.\n";
      }
      $CFG::PUPPET_ENV = $CFG::OPTS{e};
    }
    if($CFG::OPTS{f}) {
      $CFG::STEMCELL_TARBALL = $CFG::OPTS{f};
    }
    if($CFG::OPTS{i}) {
      $CFG::AUTOINSTALL = 1;
    }
    if($CFG::OPTS{m}) {
      $CFG::MEM_SIZE = DataAmount->new($CFG::OPTS{m});
      die "Illegible memory size '$CFG::OPTS{m}'\n" unless defined($CFG::MEM_SIZE->bytes());
    }
    if($CFG::OPTS{p}) {
      $CFG::START = 1;
    }
    if($CFG::OPTS{r}) {
      unless(grep { $CFG::OPTS{r} eq $_ } grep { $_ } keys %main::DISTRONAME) {
	die (sprintf "Valid values for the -r option: %s\n",
	     (join ' ', grep { $_ } sort keys %main::DISTRONAME));
      }
      $CFG::DISTRO = $CFG::OPTS{r};
    }
    if($CFG::OPTS{s}) {
      $CFG::USR_LOCAL_SIZE = DataAmount->new($CFG::OPTS{s});
      die "Illegible /usr/local size '$CFG::OPTS{s}'\n" unless defined($CFG::USR_LOCAL_SIZE->bytes());
    }
    if($CFG::OPTS{u}) {
      $CFG::NOAUTONET = 1;
    }
    if($CFG::OPTS{y}) {
      $CFG::YES = 1;
    }
  } elsif($CFG::CALLED_AS eq 'mvvm') {
    if($CFG::OPTS{c}) {
      $CFG::MVVM_DEEP = 1;
    }
  } elsif($CFG::CALLED_AS eq 'rebuild_stemcell') {
    if($CFG::OPTS{3}) {
      $CFG::ARCH = 'x86';
    }
    if($CFG::OPTS{f}) {
      $CFG::STEMCELL_TARBALL = $CFG::OPTS{f};
    }
    if($CFG::OPTS{r}) {
      my @allowed = grep { $_ ne '' } keys %main::DISTRONAME;
      unless(grep { $CFG::OPTS{r} eq $_ } @allowed) {
	die (sprintf "Valid values for the -r option: %s\n",
	     (join ' ', sort @allowed));
      }
      $CFG::DISTRO = $CFG::OPTS{r};
    }
    if($CFG::OPTS{x}) {
      $CFG::X11 = 1;
    }
  } elsif($CFG::CALLED_AS eq 'rmvm') {
    if($CFG::OPTS{y}) {
      $CFG::YES = 1;
    }
  } elsif($CFG::CALLED_AS eq 'swapvm') {
    if($CFG::OPTS{c}) {
      $CFG::SWAPVM_DEEP = 1;
    }
  }
  # Universal options
  if($CFG::OPTS{d}) {
    $CFG::DEBUG_MODE = 1;
  }
  if($CFG::OPTS{h}) {
    &main::HELP_MESSAGE();
    exit(0);
  }
  if($CFG::OPTS{t}) {
    $CFG::TEST_MODE = 1;
  }
  if($CFG::OPTS{v}) {
    &main::VERSION_MESSAGE();
    exit(0);
  }
}

sub ask_to_confirm($) {
  # Print information about what is about to happen and ask the user whether
  # this is really what they want to do.  Call with name of VM.
  my($vm_name) = @_;
  return 1 if $CFG::YES;
  if($CFG::CALLED_AS eq 'mkvm') {
    my($short) = split(/\./, $vm_name, 2);
    my $service = &determine_service($short);
    my $instance = &determine_instance($short);
    my $autoinstall = $CFG::AUTOINSTALL?'yes':'no';
    my $autonet = $CFG::NOAUTONET?'no':'yes';
    my $autostart = $CFG::NOAUTOSTART?'no':'yes';
    my $start = $CFG::START?'yes':'no';
    my $distro = $main::DISTRONAME{$CFG::DISTRO};
    my $memsize = $CFG::MEM_SIZE->in_min_base2_unit();
    my $usr_local_size = $CFG::USR_LOCAL_SIZE->in_min_base10_unit();
    my $srcpath = &stemcell_srcpath();
    print(<<"EOF");
*** You are about to create a VM with the following parameters:
    Name: $vm_name
    Guessed Service: $service
    Guessed Instance: $instance
    Distro: $distro
    Memory: $memsize
    CPUs: $CFG::NUMVCPUS
    /usr/local space: $usr_local_size
    Start VM after creating: $start
    Set VM to autostart when host boots: $autostart
    Auto-configure networking on first boot: $autonet
    Auto-run install script on first boot: $autoinstall
    Stemcell source: $srcpath
EOF
    ;
  } elsif($CFG::CALLED_AS eq 'rmvm') {
    print(<<"EOF");
*** You are about to delete the VM '$vm_name'.
    This operation cannot be undone.
EOF
    ;
  }
  my $yorn = '';
  while(1) {
    print("Are you sure you want to do this (y/n)? ");
    my $reply = <STDIN>;
    chomp($reply);
    $yorn = lc(substr($reply, 0, 1));
    last if(($yorn eq 'y') || ($yorn eq 'n'));
    print("Please answer y or n.\n");
  }
  return(($yorn eq 'y')?1:'');
}

sub vm_host_type() {
  # Returns a VM host type:
  # * 'vmw' for VMWare with individual LVs for each VM
  # * 'vmf' for VMWare with a flat LV for all VMs
  # * 'kvm' for KVM

  # If $CFG::KVM is 1, it's kvm -- this test was performed earlier
  if($CFG::KVM) {
    return 'kvm';
  }

  # At this point it must be VMWare, but which configuration?

  # If $CFG::VM_DIR is a volume of its own, then it's vmf
  if(system("df $CFG::VM_DIR >& /dev/null") >> 8) {
    return 'vmw';
  }
  return 'vmf';
}

sub stemcell_filename() {
  # Returns the name of the stemcell tarball file in standard format, based on
  # the current values of $CFG::STEMCELL, $CFG::ARCH, $CFG::DISTRO, and
  # $CFG::KVM.  This is just the filename, not an absolute or relative path.

  return(sprintf('%s-%s-%s-%s.tgz',
		 $CFG::STEMCELL,
		 $CFG::ARCH,
		 $CFG::DISTRO,
		 ($CFG::KVM)?'kvm':'vmw'));
}

sub stemcell_srcpath() {
  # Returns the full path to the stemcell tarball file, based on the return
  # value of &stemcell_filename plus the values of $CFG::STEMCELL_TARBALL and
  # $CFG::ARCHIVE_DIR.

  my $srcpath = '';

  # Examine $CFG::STEMCELL_TARBALL to make sure it makes sense and define
  # $srcpath based on it.  If it's a relative path, look for it in
  # $CFG::ARCHIVE_DIR.  If it's an absolute path, look for it where it is.  If
  # it's a directory, look for a reasonable filename in that directory.
  if($CFG::STEMCELL_TARBALL) {
    if(-d $CFG::STEMCELL_TARBALL) { # Directory -- standard filename
      $srcpath = sprintf('%s/%s', $CFG::STEMCELL_TARBALL, &stemcell_filename());
    } elsif($CFG::STEMCELL_TARBALL =~ /^\//) { # Absolute path -- use it
      $srcpath = $CFG::STEMCELL_TARBALL;
    } else { # Some other thing -- standard directory, that filename
      $srcpath = sprintf('%s/%s', $CFG::ARCHIVE_DIR, $CFG::STEMCELL_TARBALL);
    }
  } else { # $CFG::STEMCELL_TARBALL is unset
    $srcpath = sprintf('%s/%s', $CFG::ARCHIVE_DIR, &stemcell_filename());
  }
  return $srcpath;
}

sub vol_space_total() {
  # Returns a DataAmount representing the amount of space on $CFG::VM_DIR.
  my @df = split /\s+/, `df -B 1 $CFG::VM_DIR | tail -n 1`;
  chomp @df;
  debug_printf '@df = (%s)', join(', ', @df);
  return DataAmount->new($df[1].'B');
}

sub vol_space_left() {
  # Prints the amount of space left on the given volume, in bytes
  my($vol) = @_;

  return 0 unless($vol);
  my @line = split(/\s+/, `df -B 1 $vol | tail -n 1`);
  return $line[3];
}

sub test_vol_space() {
  # Given a number of bytes, see if there is at least that much space left on
  # volume $CFG::VM_DIR.  Return 1 if so, '' if not.

  my($need) = @_;
  my $room = &vol_space_left($CFG::VM_DIR);
  return($room >= $need);
}

sub vg_space_left() {
  # Returns the amount of space remaining on $CFG::VM_VG, in bytes

  my @vginfo = split(/:/, `vgdisplay -c $CFG::VM_VG`);
  # Size of a physical extent, in KB:
  my $pe_size = $vginfo[12];
  # Number of free physical extents:
  my $pe_free = $vginfo[15];

  return($pe_free * $pe_size * 1024);

}
sub test_vg_space() {
  # Given a number of bytes, see if there is at least that much space left on
  # volume group $CFG::VM_VG.  Return 1 if so, '' if not.

  my($need) = @_;
  my $room = &vg_space_left();

  return($room >= $need);
}

sub system_ram() {
  # Returns a DataAmount object representing the total amount of installed
  # system RAM.

  my @dmilines = `/usr/sbin/dmidecode --type memory | /bin/grep -E "^[[:space:]]*Size:.*\$"`;
  chomp @dmilines;
  if($CFG::DEBUG_MODE) {
    foreach my $line (@dmilines) {
      debug_printf '%s', $line;
    }
  }
  my $total = DataAmount->new("0B");
  foreach my $line (@dmilines) {
    $line =~ s/^\s+//;
    $line =~ s/([a-zA-Z])B/$1iB/;
    my(undef, $n, $u) = split(/\s+/, $line);
    next unless $n and $n =~ /^\d/;
    my $amt = DataAmount->new("$n$u");
    $total += $amt;
  }
  return $total;
}

sub system_cores() {
  # Returns the total number of cores the system has.

  my $total = 0;
  my $fh = new IO::File('</proc/cpuinfo');
  my @cpuinfolines = <$fh>;
  chomp @cpuinfolines;
  my @corelines = grep { /^\s*processor\s*:/i } @cpuinfolines;
  my %cores = map {
    my(undef, $n) = split /:/, $_;
    ($n => 1);
  } @corelines;
  my @cores = keys %cores;
  return $#cores + 1;
}

# Now some functions about making ext2/3 labels for filesystems.

sub get_partition_ext2_labels() {
  # Returns the ext2/3 filesystem labels of all partitions.

  my @parts = `fdisk -l | grep ^/dev | cut -d ' ' -f 1`;
  chomp(@parts);
  my @labels = ();
  foreach my $part (@parts) {
    pushd(@labels, `e2label $part`);
  }
  chomp(@labels);
  return(@labels);
}

sub get_lv_ext2_labels() {
  # Returns the ext2/3 filesystem labels of all LVM logical volumes.

  my @lvs = `lvs --noheadings -o vg_name,lv_name | sed -e "s/[[:space:]]\+/\//g"`;
  chomp(@lvs);
  my @labels = ();
  foreach my $lv (@lvs) {
    pushd(@labels, `e2label /dev$lv`);
  }
  chomp(@labels);
  return(@labels);
}

sub get_existing_ext2_labels() {
  # Makes a list of all the ext2 labels that exist on the system, either as
  # partitions or LVs.

  return(&get_partition_ext2_labels(), &get_lv_ext2_labels());
}

sub make_ext2_label() {
  # Given a proposed label, see if there are any ext2/3 filesystems with that
  # label already; if so, vary it with numbers until we find one that is
  # unique.  Remember that ext2/3 filesystem labels can be a maximum of 16
  # characters.  Echo the label we come up with before exiting.

  # There are really 2 potential problems this function is meant to overcome.
  # First is the prolem where the label is too long (more than 16 characters),
  # and the other is the problem where the label is nonunique (some other
  # ext2/3 filesystem exists with the same label).

  my($plabel) = @_;

  my @labels = &get_existing_ext2_labels();
  my $unique = 1;
  my $number = 1;

  # If the proposed label is too long, that won't work for us, so first let's
  # just try using the first 16 characters of the label.

  my $label = substr($plabel, 0, 16);

  # Now let's make sure it's unique.

  if(grep { $_ eq $label } @labels) {
    do {
      # Try adding $number to the end (after shortening it enough to fit)
      $label = substr($plabel, 0, 16 - length($number)).$number;
    } while(grep { $_ eq $label } @labels);
  }
  return $label;
}

# Now we have some utility functions dealing with actual VMs.

sub get_domain_by_name($) {
  # Basically a workaround for the fact that Sys::Virt::get_domain_by_name()
  # causes the entire script to die if no domain exists with the given name.  I
  # don't want that; I just want an undef value that I can test for.  I wish
  # Sys::Virt weren't written as it is, but oh well.  Returns a
  # Sys::Virt::Domain object, or undef if no domain with the given name exists.
  my($vm) = @_;
  return undef unless $vm;	# Undefined or null names are bad anyway
  my $dom = undef;
  my @domains = grep {
    $_->get_name() eq $vm;
  } $CFG::VMM->list_all_domains();
  return undef if $#domains == -1;
  if($#domains > 0) {
    # This would be a very odd situation: more than one domain with the same
    # name.  Normally @domains should have one element ($#domains should be 0).
    warn "ERROR: Discovered more than one domain with name '$vm'! Investigate!\n";
  }
  ($dom) = @domains;	# Assign $dom the value of the first element of @domains.
  return $dom;
}

sub vm_running() {
  # See if the given VM is running.

  # For KVM, we use Sys::Virt to obtain a domain object for the given VM and
  # then query the domain object's is_active method.

  # For VMware, this is done by issuing the command
  # "vmware-cmd <.vmx file> getstate", whose output is one of:

  # getstate() = on
  # getstate() = off

  # A return value of 1 means the VM is running.  A return value of '' means
  # that it is not.

  my($name) = @_;

  return '' if($CFG::TEST_MODE);
  if($CFG::KVM) {
    my $dom = get_domain_by_name $name;
    unless($dom) {
      die "Error: VM '$name' does not exist\n";
    }
    if($dom->is_active()) {
      return 1;
    } else {
      return '';
    }
  } else { # VMware
    my $vmxpath = "$CFG::VM_DIR/$name/$name.vmx";
    unless(-e $vmxpath) {
      die "Error: File $vmxpath does not exist\n";
    }
    my $state = `/usr/bin/vmware-cmd $vmxpath getstate 2> /dev/null | sed -re 's/^.*=[[:space:]]*//'`;
    chomp($state);
    debug_printf "\$state = '%s'", $state;
    if($state eq 'on') {
      return 1;
    } else {
      return '';
    }
  }
}

sub set_owners_perms() {
  # Set the ownerships and permissions of the files in a VMware directory to
  # satisfactory values for our purposes.  Returns true on success, false on
  # failure.

  my($vmdir) = @_;
  my $result;

  $result = &test_cmd("chgrp -R vm $vmdir");
  return '' unless($result == 0);
  $result = &test_cmd("chmod g+rwxs $vmdir");
  return '' unless($result == 0);
  $result = &test_cmd("chmod u+x $vmdir/*.vmx");
  return '' unless($result == 0);
  # Copy user permissions onto group permissions.
  $result = &test_cmd("chmod -R g=u $vmdir");
  return '' unless($result == 0);
  return 1;
}

sub register_vm() {
  # Tell VMware to open this VM and add it to its inventory.  Returns true on
  # success, false on failure.

  my($vm) = @_;
  my $result;

  $result = &test_cmd("vmware-cmd -s register $CFG::VM_DIR/$vm/$vm.vmx 2> /dev/null");
  return '' unless($result == 0);
  return 1;
}

sub unregister_vm() {
  # Tell VMware to remove this VM from its inventory.

  my($vm) = @_;
  my $result;

  debug_printf "Unregistering VM %s", $vm;
  $result = &test_cmd("vmware-cmd -s unregister $CFG::VM_DIR/$vm/$vm.vmx 2> /dev/null");
  if($result == 0) {
    return 1;
  } else {
    return '';
  }
}

sub sethashval(\%$$) {
  # Recursive utility routine for handling VMware-style hierarchical config
  # variables.  Makes sure that, for example, ide0:0.present (from a VMware
  # .vmx file) becomes $href->{ide0:0}->{present}.
  my($href, $k, $v) = @_;
  if($k =~ /\./) {
    my($subk, $rest) = split(/\./, $k, 2);
    my $subkref = $subk."_ref";
    unless(exists($href->{$subkref})) {
      $href->{$subkref} = {};
    }
    &sethashval($href->{$subkref}, $rest, $v);
  } else {
    $href->{"${k}_val"} = $v;
  }
}

sub read_vmxfile($) {
  # Reads a .vmx file, returning a reference to an array and a reference to a
  # hash.  The array has the keywords in order, while the hash has the keyword-value pairs.

  my($file) = @_;
  my(@keywords, %data);
  if($CFG::TEST_MODE) {
    # No .vmx file to read, so just make some stuff up for testing
    my(@path) = split(/\//, $file);
    my $vmxfile = $path[$#path];
    my $vm = $vmxfile;
    $vm =~ s/\.vmx//;
    @keywords =
      qw(
	  displayname
	  autostart
	  memsize
	  numvcpus
	  ethernet0.present
	  ethernet0.address
	  ethernet1.present
	  ethernet1.address
	  ide0:0.present
	  ide0:0.filename
	  ide0:1.present
	  ide0:1.filename
       );
    %data =
      (
       displayname_val => $vm,
       autostart_val => 'poweron',
       memsize_val => '1024',
       numvcpus_val => '1',
       'ethernet0_ref' =>
       {
	'present_val' => 'TRUE',
	'address_val' => '00:50:56:04:00:00',
       },
       'ethernet1_ref' =>
       {
	'present_val' => 'TRUE',
	'address_val' => '00:50:56:06:00:00',
       },
       'ide0:0_ref' =>
       {
	'present_val' => 'TRUE',
	'filename_val' => 'hda.vmdk',
       },
       'ide0:1_ref' =>
       {
	'present_val' => 'TRUE',
	'filename_val' => 'hdb.vmdk',
       },
      );
  } else {
    my $fh = new IO::File();
    unless($fh->open("<$file")) {
      carp "Unable to open $file for reading: $!";
      return('', '');
    }
    my $line;
    while(defined($line = <$fh>)) {
      # Skip blank lines
      next if($line =~ /^\s*$/);
      # Skip comments
      next if($line =~ /^\s*#/);
      # Normal format for a setting is
      #
      # keyword = "value"
      #
      # but occasionally the value won't be in quotation marks and there won't
      # be spaces before and after the = sign.
      if(($line =~ /^\s*[\w:.]+\s*=\s*.*\s*$/) || ($line =~ /^\s*[\w:.]+\s*=\s*".*"\s*$/)) {
	my($key, $value) = ($line =~ /^\s*([\w:.]+)\s*=\s*(.*?)\s*$/);
	# The keywords are actually case-insensitive, but they appear with
	# various capitalizations
	$key = lc($key);
	if($value =~ /^".*"$/) {
	  ($value) = ($value =~ /^"(.*)"$/);
	}
	push(@keywords, $key);
	&sethashval(\%data, $key, $value);
      }
    }
    $fh->close();
  }
  return(\@keywords, \%data);
}

sub modify_vmxfile($\%) {
  # Edits a .vmx file, changing parameters to the given values.  Parameters in
  # .vmx files look like:
  #
  # parameter = "value"
  #
  # The first parameter to this function should be the path to the .vmx file.
  # After that, the parameters should be in pairs, with the name and value of
  # each parameter coming right after the other.  If a parameter exists in the
  # .vmx file already, its value will of course be replaced with the new value.
  # Otherwise, the new parameter will be added to the end.  Note that there is
  # no way for this function to discriminate between valid and invalid
  # parameters -- VMware has never been very forthcoming about documenting
  # these parameters, and the VMware Server 1.x documentation is no longer
  # available from their web server.  Some useful parameters:
  #
  # displayname: the name of the VM; VMware refers to it by this name
  # autostart: whether the VMware server should start this VM automatically
  # ("poweron") or not ("none")
  # memsize: the amount of RAM available to the VM, measured in MiB
  # numvcpus: the number of virtual CPUs (1 or 2)
  # machine.id: a string that can be retrieved by vmware_guestd within the guest
  #
  # The previous .vmx file will be left as *.vmx.bak.

  # Returns true on success, false if there was a problem of some sort.

  my($vmxfile, $changes) = @_;
  my $result;
  my %existed = ();
  $result = &test_cmd("mv $vmxfile $vmxfile.bak");
  return '' unless($result == 0);
  if($CFG::TEST_MODE) {
    test_printf 'modify %s', $vmxfile;
    return 1;
  }
  my $rh = IO::File->new();
  $rh->open("<$vmxfile.bak") || die "Unable to open $vmxfile.bak for reading: $!\n";
  return '' unless $rh;
  my $wh = IO::File->new();
  $wh->open(">$vmxfile") || die "Unable to open $vmxfile for writing: $!\n";
  return '' unless $wh;
  my $line;
  # Read $vmxfile.bak line by line, printing output to $vmxfile
  while(defined($line = <$rh>)) {
    chomp($line);
    unless(($line =~ /^\s*#/) || ($line =~ /^\s*$/)) { # Ignore comments/blank lines
      # Get the parameter name
      my($key) = ($line =~ /^\s*([^\s=]+)/);
      # If this parameter is being changed, remember it in %existed and rewrite $line
      if(exists($changes->{$key})) {
	$existed{$key} = 1;
	$line = sprintf('%s = "%s"', $key, $changes->{$key});
      }
    }
    $wh->printf("%s\n", $line);
  }
  # Any parameters in %$changes that didn't exist in the file should be added
  # to the end
  foreach my $key (keys(%$changes)) {
    unless($existed{$key}) {
      $wh->printf("%s = \"%s\"\n", $key, $changes->{$key});
    }
  }
  $wh->close();
  $rh->close();
  return 1;
}

sub vm_name_valid() {
  # Tests the proposed VM name to make sure it's legal for LVM and fits within
  # our expectations.  LVM doesn't allow VG or LV names with any characters
  # other than letters numbers, and _.+-. We want all VM names to end with a
  # period and a version number. Returns 1 if all is well, 0 otherwise.

  my($name) = @_;

  return '' unless(defined($name));
  return '' if($name eq '');
  if($name =~ /[^-a-z0-9_.+]/) {
    warn "ERROR: VM name may contain letters, numbers, and the characters -_.+ only.\n";
    return '';
  }
  if($name !~ /\.\d+$/) {
    warn "ERROR: VM name must end in .<version>, where <version> is numeric.\n";
    return '';
  }
  return 1;
}

sub vm_name_exists($$) {
  # Checks whether a VM already exists under the given name, or does not.  If
  # it does, return true (1).  If not, return false ('').  If $supposed_to is
  # true, print warning messages based on the assumption that it should exist
  # (i.e. if it doesn't, warn).  If $supposed_to is false, warn if the VM does
  # exist.

  my($vm_name, $supposed_to) = @_;

  return($supposed_to) if($CFG::TEST_MODE);
  # If it's KVM, see if there's a VM with that name.
  if($CFG::KVM) {
    if(grep { $_ eq $vm_name } map { $_->get_name() } $CFG::VMM->list_all_domains()) {
      carp "A VM named $vm_name already exists." unless($supposed_to);
      return 1;
    } else {
      carp "No VM named $vm_name exists." if($supposed_to);
      return '';
    }
  }
  # Flat VMware is easier.  But let's test for some pathological cases possible
  # with non-flat VMware first.
  if($CFG::VM_HOST_TYPE eq 'vmw') {
    # Look for an LV named $vm_name.
    if((system("lvdisplay /dev/$CFG::VM_VG/$vm_name >& /dev/null") >> 8) == 0) {
      unless($supposed_to) {
	carp "A logical volume named /dev/$CFG::VM_VG/$vm_name already exists.";
	return 1;
      }
    } else {
      if($supposed_to) {
	carp "No logical volume named /dev/$CFG::VM_VG/$vm_name exists.";
	return '';
      }
    }
    # Look for a mount point named $vm_name.
    if(-e "$CFG::VM_DIR/$vm_name") {
      unless($supposed_to) {
	carp "$CFG::VM_DIR/$vm_name already exists.";
	return 1;
      }
    } else {
      if($supposed_to) {
	carp "$CFG::VM_DIR/$vm_name does not exist.";
	return '';
      }
    }
    # Look for an /etc/fstab entry for $vm_name.
    if((system("grep -Eq ^[^[:space:]]+[[:space:]]+$CFG::VM_DIR/$vm_name/?[[:space:]] /etc/fstab") >> 8) == 0) {
      unless($supposed_to) {
	carp "There is an entry in /etc/fstab for $CFG::VM_DIR/$vm_name.";
	return 1;
      }
    } else {
      if($supposed_to) {
	carp "There is no entry in /etc/fstab for $CFG::VM_DIR/$vm_name.";
	return '';
      }
    }
  }
  # Then there are problems that can occur on any VMware host, flat or not.
  # For example, there might be a .vmx file with the name.
  if((system("ls $CFG::VM_DIR/*/$vm_name.vmx >& /dev/null") >> 8) == 0) {
    unless($supposed_to) {
      my $where = `ls $CFG::VM_DIR/*/$vm_name.vmx`;
      chomp($where);
      carp "$where already exists.";
      return 1;
    }
  } else {
    if($supposed_to) {
      carp "Cannot find $CFG::VM_DIR/*/$vm_name.vmx.";
      return '';
    }
  }
  # One last crazy check.  There might be a VM with everything else different
  # but with the same displayname.
  if((system("grep -Eiq '^[[:space:]]*displayname[[:space:]]*=[[:space:]]*\"$vm_name\"' $CFG::VM_DIR/*/*.vmx") >> 8) == 0) {
    unless($supposed_to) {
      carp "The following .vmx files define VMs named '$vm_name':";
      system("grep -Eil '^[[:space:]]*displayname[[:space:]]*=[[:space:]]*\"$vm_name\"' $CFG::VM_DIR/*/*.vmx > /dev/stderr");
      return 1;
    }
  } else {
    if($supposed_to) {
      carp "No .vmx file in $CFG::VM_DIR/*/*.vmx defines a VM named '$vm_name'.";
      return '';
    }
  }
  # At this point it certainly looks as if the proposed VM is how it's supposed
  # to be.
  return $supposed_to?1:'';
}

sub vm_name_ok() {
  # Make sure a proposed VM name is OK -- is it valid?  Does it already exist?
  # If all is well, return true.  If not, return false.

  my($vm_name) = @_;
  if(&vm_name_valid($vm_name) && !&vm_name_exists($vm_name, '')) {
    return 1;
  } else {
    return '';
  }
}

sub have_enough_space {
  # Make sure the size of the /usr/local disk makes sense, we have space for
  # it, etc.  If all is well, returns true.

  # Make sure the size is intelligible
  my $usr_local_size = $CFG::USR_LOCAL_SIZE;
  # Make sure we have enough space
  my $usr_local_size_bytes = $usr_local_size->bytes();
  my $other_data_bytes = $CFG::BASE_VM_SIZE->bytes();
  my $total_bytes = $usr_local_size_bytes + $other_data_bytes;
  my $vm_size_bytes = $total_bytes*2;
  my $is_enough_space;
  my $space_left_bytes;

  # Test whether there is enough space -- on the volume group if "old style"
  # VMware, or on the volume itself if "flat" VMware or if KVM.
  if(($CFG::VM_HOST_TYPE eq 'vmf') || ($CFG::VM_HOST_TYPE eq 'kvm')) {
    $is_enough_space = &test_vol_space($vm_size_bytes);
    $space_left_bytes = &vol_space_left($CFG::VM_DIR);
  } else {
    $is_enough_space = &test_vg_space($vm_size_bytes);
    $space_left_bytes = &vg_space_left();
  }
  unless($is_enough_space) {
    if(($CFG::VM_HOST_TYPE eq 'vmf') || ($CFG::VM_HOST_TYPE eq 'kvm')) {
      carp "Not enough room left on volume $CFG::VM_DIR";
    } else {
      carp "Not enough room left on volume group $CFG::VM_VG";
    }
    carp (sprintf "%.0f MiB left; requires %.0f",
	  $space_left_bytes/1048576,
	  $vm_size_bytes/1048576);
    return '';
  }

  # Test whether the requested size is outside the supported limits of the
  # virtual disk system.  VMware Server 1.x's documentation states limits of no
  # less than 100.0 MB and no greater than 950.0 GB.  I am uncertain what the
  # limits of the KVM virtual disk format that we're using (QCOW2) are.
  unless($CFG::KVM) {
    # Check the $CFG::USR_LOCAL_SIZE to make sure it's not too big or small
    # (VMware's stated limits are [100.0 MB, 950.0 GB])
    if(($usr_local_size_bytes < 100000000) ||
       ($usr_local_size_bytes > 950000000000)) {
      carp "Virtual disk /usr/local cannot be smaller than 100 MB or larger than 950 GB";
      return '';
    }
  }

  # Things seem OK
  return 1;
}

sub have_x11() {
  # Returns true if we have the capability to run X11 clients; false otherwise.
  if((system("xset q >& /dev/null") >> 8) == 0) {
    return 1;
  } else {
    return '';
  }
}

sub create_vdisk_img($\$$$$) {
  # Arguments:
  # * Path to disk image file to create
  # * Size of virtual disk to create (a DataAmount)
  # * Flag: Partition disk and make filesystem on it?
  # * Label: Label to give filesystem
  # * Blocksize: Size of blocks on filesystem

  # Creates a virtual disk image in the current directory with the given name
  # and size (normally a data amount in G, such as "32G").  If $CFG::KVM,
  # create a QCOW2 (QEMU Cache-on-Write 2) image; otherwise, create a VMware
  # image.

  # If the third argument is true, creates a partition on the disk image and
  # makes a filesystem in that partition (ext3 for RHEL <=5, ext4 for RHEL >=
  # 6).  If the third argument is false, don't create any partitions on it
  # (usually because Anaconda will be doing this itself).

  # The filesystem will get the specified label, or "/usr/local" by default.
  # It will also get the specified blocksize (only values of 1024, 2048, and
  # 4096 are allowed) unless nothing is specified, in which case 1024 is the
  # default.

  # Returns true on success, false on failure.

  my($filename, $size, $partfs, $label, $blocksize) = @_;
  my $result;

  unless($filename) {
    # This would be a programming error.
    carp "Empty virtual disk filename.";
    exit 1;
  }
  unless(defined($size) && defined($size->bytes())) {
    # This would also be a programming error.
    carp "No virtual disk size given.";
    exit 1
  }
  my $size2 = $size->in_min_base2_unit_lvm(1);
  $label ||= '/usr/local';
  $blocksize ||= 1024;
  # Only these values are allowed for the block size in ext2/3/4 filesystems.
  if(($blocksize != 1024) && ($blocksize != 2048) && ($blocksize != 4096)) {
    $blocksize ||= 1024;
  }
  # Choose default filesystem based on $CFG::DISTRO.  May have to modify this
  # if we add other distros.
  my $fs = ($CFG::DISTRO eq '5')?'ext3':'ext4';
  if($CFG::KVM) {
    # For KVM, we create it with qemu-img create, then use libguestfs to
    # directly partition it and make a filesystem on it.
    print("Creating QCOW2 disk image $filename ...\n");
    $result = &test_cmd("qemu-img create -f qcow2 -o size=$size2,preallocation=metadata $filename >/dev/null");
    return '' unless($result == 0);
    if($partfs) {
      print("Creating /usr/local partition and filesystem ...\n");
      if($CFG::TEST_MODE) {
	test_printf "using libguestfs to partition disk image and make filesystem on its first and only partition";
      } else {
	my $g = Sys::Guestfs->new();
	try {
	  $g->add_drive($filename);
	};
	unless($@ eq '') {
	  croak "Sys::Guestfs unable to add drive $filename: $@";
	}
	try {
	  $g->launch;
	};
	unless($@ eq '') {
	  croak "Sys::Guestfs unable to launch: $@";
	}
	my $gdisk;
	try {
	  $gdisk = $g->list_devices;
	};
	unless($@ eq '') {
	  croak "Sys::Guestfs unable to get list of devices: $@";
	}
	try {
	  $g->part_disk($gdisk, "gpt");
	};
	unless($@ eq '') {
	  croak "Sys::Guestfs unable to partition disk $gdisk: $@";
	}
	my $gpart;
	try {
	  $gpart = $g->list_partitions;
	};
	unless($@ eq '') {
	  croak "Sys::Guestfs unable to list partitions: $@";
	}
	try {
	  $g->mkfs($fs, $gpart, blocksize => $blocksize);
	};
	unless($@ eq '') {
	  croak "Sys::Guestfs unable to create filesystem: $@";
	}
	try {
	  $g->set_label($gpart, $label);
	};
	unless($@ eq '') {
	  croak "Sys::Guestfs unable to set filesystem label: $@";
	}
	try {
	  $g->shutdown;
	};
	try {
	  $g->close;
	};
      }
    }
    $result = &test_cmd("chown qemu:qemu $filename");
    return '' unless($result == 0);
  } else {
    # For VMware, we make a raw disk image, partition it, make a filesystem on
    # it, and convert it, using "qemu-img convert". VMware (or, at least,
    # VMware Server 1.x) has no utilities for accessing the data within a .vmdk
    # virtual disk image file or converting other types of disk images to .vmdk
    # files. However, the qemu-img command can convert between disk image
    # formats, and it exists for RHEL 5. This process is based on an idea by
    # Soichi Hayashi (hayashis@iu.edu).
    my $size_m = $size->in_min_base2_unit();
    my $size_mib = $size->in('MiB');
    # Make the raw disk image -- if we're not partitioning it, just use
    # vmware-vdiskmanager to make it
    if($partfs) {
      my $tempdir;
      if($CFG::TEST_MODE) {
	# In test mode, the VM-specific directory hasn't been made, and we don't
	# want to create an actual tempdir, so just make up a fictional one.
	$tempdir = "$CFG::VM_DIR/tmp";
      } else {
	$tempdir = File::Temp::tempdir('mkvm.XXXXXXXX', DIR => dirname($filename), CLEANUP => 1);
      }
      my $tempdisk = "$tempdir/tempdisk.img";
      my $size_blocks = int($size->in('kiB')/4);
      my $size_mb = $size->in_unit('MB');
      print("Creating raw disk image $tempdisk of size ${size_mb} ...\n");
      $result = &test_cmd("dd if=/dev/zero of=$tempdisk bs=4096 count=${size_blocks} > /dev/null");
      return '' unless($result == 0);
      # Partition the raw disk image
      print("Creating partition within $tempdisk ...\n");
      $result = &test_cmd("parted $tempdisk mktable gpt mkpart primary ext3 '0%' '100%'");
      return '' unless($result == 0);
      print("Creating filesystem within partition ...\n");
      # Find out where that partition starts and how big it is
      my($partoffset_b, $partsize_b);
      if($CFG::TEST_MODE) {
	# Make up some reasonable-ish values for testing
	$partoffset_b = 16384;
	$partsize_b = 1048576*$size_mib - $partoffset_b;
      } else {
	my @partout = grep { /^\s*\d/ } `parted $tempdisk unit b print`;
	($partoffset_b, $partsize_b) = ($partout[0] =~ /^\s*\d+\s+(\d+)B\s+\d+B\s+(\d+)B/);
      }
      # Define the image as a loopback device with the offset just discovered
      $result = &test_cmd("losetup -f -o $partoffset_b $tempdisk");
      return '' unless($result == 0);
      my $loopdev;
      if($CFG::TEST_MODE) {
	$loopdev = '/dev/loop0';
      } else {
	my @lout = grep { m!\($tempdisk\)! } `losetup -a`;
	($loopdev) = ($lout[0] =~ /^([^:]+)/);
      }
      # Make a filesystem on that loopback device
      my $blocks = sprintf("%d", $partsize_b/$blocksize);
      my $cmd = sprintf("mkfs -t %s -L '%s' -b %d %s %d", $fs, $label, $blocksize, $loopdev, $blocks);
      $cmd .= ' > /dev/null' unless($CFG::DEBUG_MODE);
      debug_printf "mkfs command: %s", $cmd;
      return '' unless(&test_cmd($cmd) == 0);
      # Release the loopback device; we're done with it
      $result = &test_cmd("losetup -d $loopdev");
      return '' unless($result == 0);
      # Convert the partition to VMware
      printf("Converting disk image to vmdk ...\n");
      $result = &test_cmd("qemu-img convert -f raw $tempdisk -O vmdk $filename");
      return '' unless($result == 0);
      # Clean up
      $result = &test_cmd("rm -rf $tempdir");
      return '' unless($result == 0);
    } else {
      # Not partitioning it -- save time by just using vmware-vdiskmanager to create it
      $result = &test_cmd("vmware-vdiskmanager -c -s ${size_mib}Mb -t 0 -a ide $filename");
      return '' unless($result == 0);
    }
    $result = &test_cmd("chgrp vm $filename");
    return '' unless($result == 0);
  }
  print("Done creating image.\n");
  return 1;
}

sub convert_vmware_img_to_kvm($$) {
  # Converts a VMware disk image file to a KVM QCOW2 disk image file.  The
  # VMware disk image file must be monolithic and have no snapshots.
  my($src, $dest) = @_;
  &test_cmd("qemu-img convert -O qcow2 -o preallocation=metadata $src $dest");
}

sub prepare_vm_home($) {
  # Prepares a home for the VM -- in the case of non-flat VMware hosts, this
  # means making a LV, making a filesystem on it, making an /etc/fstab entry
  # for it, making a mount point, and mounting it.  For flat VMware hosts, this
  # just means making a directory for it.  For KVM hosts, this means doing
  # nothing.  Requires $CFG::MEM_SIZE, $CFG::USR_LOCAL_SIZE, etc. to be set.

  # Returns true on success, false on failure.

  my($vmname) = @_;
  my $result;
  # Unless it's KVM, make the mount point
  unless($CFG::KVM) {
    $result = &test_cmd("mkdir $CFG::VM_DIR/$vmname");
    return '' unless($result == 0);
    $result = &test_cmd("chgrp vm $CFG::VM_DIR/$vmname");
    return '' unless($result == 0);
    $result = &test_cmd("chmod g+ws $CFG::VM_DIR/$vmname");
    return '' unless($result == 0);
  }

  # For non-flat VMware, do the necessary stuff
  if($CFG::VM_HOST_TYPE eq 'vmw') {
    # Make the LV
    my $vm_size_lvm = (2*($CFG::BASE_VM_SIZE + $CFG::USR_LOCAL_SIZE))->in_min_base2_unit_lvm(1);
    $result = &test_cmd("lvcreate --addtag $CFG::VM_TAG -L $vm_size_lvm -n $vmname $CFG::VM_VG");
    return '' unless($result == 0);

    # Generate the filesystem label
    my $vm_ext2_label = &make_ext2_label($vmname);

    # Make the filesystem
    $result = &test_cmd("mkfs -t ext3 -L $vm_ext2_label /dev/$CFG::VM_VG/$vmname");
    return '' unless($result == 0);

    # Make a line in /etc/fstab
    $result = &test_cmd("echo 'LABEL=$vm_ext2_label	$CFG::VM_DIR/$vmname	ext3	defaults	1 2\" >> /etc/fstab");
    return '' unless($result == 0);

    # Mount the new volume
    $result = &test_cmd("mount $CFG::VM_DIR/$vmname");
    return '' unless($result == 0);
  }
  return 1;
}

sub remove_vm_home($) {
  # Remove the VM's home -- in the case of (flat, because by the time this was
  # written there were no longer any non-flat ones and never will be again)
  # VMware hosts, this means deleting the directory.  In the case of KVM hosts,
  # do nothing.  This is called by do_rmvm, but also by do_mkvm if
  # install_stemcell or customize_vm fails.

  # Returns true on success, false on failure.

  my($vmname) = @_;
  unless($vmname) {
    carp "ERROR: \$vmname blank in remove_vm_home";
    return '';
  }
  my $result;
  unless($CFG::KVM) {
    my $vmdir = "$CFG::VM_DIR/$vmname";
    if($CFG::VM_HOST_TYPE eq 'vmw') {
      # Unmount the volume.
      return '' unless(&test_cmd("umount $vmdir") == 0);
    }
    # Remove the subdirectory or mount point.
    debug_printf "Deleting directory %s", $vmdir;
    return '' unless (&test_cmd("rm -rf $vmdir") == 0);
    # Remove the mount line from /etc/fstab.
    if($CFG::VM_HOST_TYPE eq 'vmw') {
      $result = &test_cmd("cp --preserve=all /etc/fstab /etc/fstab.bak");
      return '' unless($result == 0);
      $result = &test_cmd("grep -Ev ^[^[:space:]]+[[:space:]]+$vmdir/?[[:space:]] /etc/fstab.bak > /etc/fstab");
      return '' unless($result == 0);
      # Get rid of the LV, first waiting a few seconds to make sure things
      # settle down (rmvm has crashed LVM in the past; it's good to be careful
      # here).
      sleep(3);
      # Switch the LV to non-active.  This may also help to prevent LVM
      # trouble.
      $result = &test_cmd("lvchange -a n /dev/$CFG::VM_VG/$vmname");
      return '' unless($result == 0);
      sleep(3);
      $result = &test_cmd("lvremove /dev/$CFG::VM_VG/$vmname");
      return '' unless($result == 0);
    }
  }
  return 1;
}

sub ip_canonical($;$) {
  # Given a NetAddr::IP object, returns the address or address/mask using the
  # short version of the IP if IPv6 or the long version if IPv4.  The
  # NetAddr::IP module doesn't have anything like this.  It has the 'addr' and
  # 'cidr' methods, which returns address and address/mask respectively, but
  # the IPv6 address is always in its medium-long form, meaning it includes all
  # zeros (fd2f:6feb:37:1::2a -> fd2f:6feb:37:1:0:0:0:2a).  It has the 'short'
  # method, which returns IPv6 addresses in their properly shortened forms, but
  # it also shortens IPv4 addresses (127.0.0.1 -> 127.1), which is generally
  # not what you want.
  my($ip, $mask) = @_;
  return undef unless $ip and ref($ip) eq 'NetAddr::IP';
  my $result;
  if($ip->version eq '4') {
    $result = $ip->addr;
  } elsif($ip->version eq '6') {
    $result = $ip->short;
  } else {
    warn "Script not compatible with IPv".$ip->version."\n";
    return undef;
  }
  if($mask) {
    $result .= '/'.$ip->masklen;
  }
  return $result;
}

sub construct_hw_address($$\%) {
  # Constructs a hardware address for one of a VM's network interfaces.  The
  # parameters are the VM name, a string whose value should be either 'public'
  # (if this is the public network interface, which is normally eth0) or
  # 'private' (if it's the private one, normally eth1), and a network data
  # structure such as that produced by lookup_network_params.  The address is
  # stored in $net->{public}->{hwaddr} (or {private}).  This subroutine should
  # really only be called by &lookup_network_params() and
  # &build_vm_pxe_anaconda().

  # In the case of rebuilding a stemcell, we need this hardware address in
  # order to signal Cobbler to automatically select the appropriate PXE boot
  # profile and thus build a stemcell image for the requested distro.  In the
  # case of creating a VM via a stemcell image, we still need this in order to
  # generate unique hardware addresses for each interface.

  # It is important that no two devices on the same LAN have the same hardware
  # address; packet collisions can occur if this happens.  It is also important
  # for each network interface on the same computer to have a unique hardware
  # address, so the operating system can assign the appropriate device name and
  # IP addresses to the correct interface.

  # What the hardware address needs to be like:
  #
  # * If we're rebuilding a stemcell, we need a hardware address that tells
  # Cobbler to use the appropriate profile.
  #
  # * Otherwise, we need a hardware address that is guaranteed unique across
  # whatever networks the VM is connected to.  Obviously we can't control what
  # addresses are used by anything other than VMs created by this script, but
  # we can make sure that the ones generated by this script are unique.  Then
  # we can just make sure that nothing else uses the same prefixes.
  #
  # We have a problem, though.  In the past, we had 8 bits' worth of IP address
  # to fit into the 22 bits we had to work with in the EUI-48 address.  (The
  # public subnet actually only gave us 8 bits: 129.79.53.0/24.  The private
  # subnet was 192.168.96.0/22, but I'd defined things such that all VMs had
  # prefix 192.168.97.0/24.)  We actually didn't need to put the last 2 octets
  # of the IP into the hardware address -- we could have gotten away with just
  # the last octet, since we were using another bit to differentiate the public
  # and private interfaces.
  #
  # The problem now is that we have 38 bits to work with, even in the best case
  # of EUI-64 addresses, but a 64-bit address space to fit into it for each
  # network.  And of the 38 bits available to us in the EUI-64 address, we'll
  # have to reserve one to denote whether the address was randomly generated or
  # not (in the extremely rare case that the randomly generated bits are equal
  # to an IP-based address that exists on one of the subnets), and another one
  # to denote whether this is the public or private interface (in the extremely
  # rare case that the public and private IP addresses' last 64 bits are
  # equal).
  #
  # A further problem is that libvirt won't accept EUI-64 addresses.
  # Apparently no one developing libvirt has ever heard of them.  If you try to
  # put one in the "<mac address=''>" tag in the XML that defines a domain, you get
  #
  # libvirt error code: 27, message: XML error: unable to parse mac address '<address>'
  #
  # So that makes things even worse.  We only have EUI-48 addresses, so we don't
  # have 38 bits to work with; we only have 22.
  #
  # How we will generate the EUI-48 address:
  #
  # 1. Is the IPv6 address of the interface known?
  #   Yes: Obtain the 20 lowest bits of the IPv6 address.
  #   No: Is the IPv4 address of the interface known?
  #     Yes: Obtain the 20 lowest bits of the IPv4 address.
  #     No: Generate 20 random bits.
  #
  # 2. Shift those 20 bits left by one and set the low bit equal to 1 if this
  # is the private interface, and 0 if not.  There are now 21 bits, and there
  # is no chance of a collision in the very rare case that the public and
  # private interfaces should happen to give us an identical set of 20 bits in
  # step 1.
  #
  # 3. Set the 22nd bit to 1 if the address was randomly generated, and 0 if
  # not.  There is now no possibility of a collision in the very rare case that
  # the 21 low bits should be identical with the 21 low bits of some other
  # hardware address on the network that was set based on IPv4/6 addresses.
  # There is also a very low chance that the 21 low bits of some other
  # randomly-generated hardware address on the network being the same as those
  # of this EUI-48 address.
  #
  # 4. Set the rest of the bits in the address to the prescribed sequence for
  # the type of VM.
  #
  # Bit usage diagram for EUI-48 address:
  # Octet 1           \
  # Octet 2            \ Prescribed by type of VM
  # Octet 3            /
  # Octet 4, bits 6-7 /
  # Octet 4, bit 5: 1=IP section randomly generated, 0=IP section based on IP
  # Octet 4, bits 0-4 \
  # Octet 5           | Bottom 20 bits of IP (if known) or randomly generated
  # Octet 6, bits 1-7 /
  # Octet 6, bit 0: 1=private interface, 0=public interface
  #
  # If we could use EUI-64 addresses, this would be the bit usage diagram:
  # Octet 1           \
  # Octet 2            \ Prescribed by type of VM
  # Octet 3            /
  # Octet 4, bits 6-7 /
  # Octet 4, bit 5: 1=IP section randomly generated, 0=IP section based on IP
  # Octet 4, bits 0-4 \
  # Octet 5            \
  # Octet 6            | Bottom 36 bits of IP (if known) or randomly generated
  # Octet 7            /
  # Octet 8, bits 1-7 /
  # Octet 8, bit 0: 1=private interface, 0=public interface
  #
  # Chances of an address collision between this VM and some other VM on the
  # network (which we'll call X): There are 3 cases.
  #
  # 1. If this VM and X's IP addresses are both IP-based (and not randomly
  # generated): There is no chance of address collision, because the IP
  # addresses must differ, and their differences will appear in the 20 lower
  # bits unless there are an impossible number of machines on the subnet.
  # Seriously, there would need to be at least 2^20 (over a million) machines
  # on the subnet for this type of collision to occur.
  #
  # 2. If one of the two VMs has a randomly-generated address, there is no
  # chance of address collision, even if the randomly-generated 20 bits are
  # identical to the other VM's IP-based 20 bits, because that 22nd bit will be
  # 0 for one of the VMs and 1 for the other.
  #
  # 3. If both of the VMs have randomly-generated addresses, there is a 1 in
  # 2^20 chance (or approximately 1 in a million) of an address collision.
  # Obviously this chance will increase with the number of randomly-generated
  # addresses on the subnet (the birthday paradox).
  #
  # Chances of an address collision between the two interfaces on this VM are
  # zero, because the lowest bit will always be set to 0 for the public
  # interface and 1 for the private interface.
  #
  # Example: myosg1 has public IPv6 address 2001:18e8:2:6::168 and private IPv6
  # address fd2f:6feb:37:1::18.  The bottom 20 bits of each of these are 0x168
  # and 0x18, respectively.  Shifting them left by 1 produces 0x2d0 and 0x30,
  # respectively.  The private address gets its low bit set, producing 0x2d0
  # and 0x31.  Thus, if this were a KVM VM, our EUI-48 public and private
  # addresses would be 52:54:00:00:02:d0 and 52:54:00::00:00:31, respectively.
  # Note that the private address ends up with an odd last digit -- because we
  # shift left by one bit and then set the low bit of only the private address,
  # all public addresses will end with an even last digit, while all private
  # ones will end with an odd one.
  #
  # The minority case where the VM has an IPv4 address but no IPv6 address is
  # one that I expect will disappear over time, but there will be a few to
  # start with.  In this case, where we use the low 20 bits of the IPv4 address
  # there is still a possibility of collision.
  #
  # Example: At time of writing this, repo1 has public IPv4 address
  # 129.79.53.72, private IPv4 address 192.168.97.68, and no IPv6 addresses.
  # In hex these are 0x814f3548 and 0xc0a86144.  Masking off the bottom 20 bits
  # gives 0xf3548 and 0x86144.  Shifting left by 1 additional bit produces
  # 0x1e6a90 and 0x10c288.  Then we set the low bit on the private address,
  # producing 0x1e6a90 and 0x10c289.  Suppose for this example that this is a
  # KVM VM, so we'll use the prefix the libvirt people recommend for that, so
  # our EUI-48 public and private addresses would then be 52:54:00:1e:6a:90 and
  # 52:54:00:10:c2:89.  Those two will never collide with each other because of
  # that last bit.  Is it possible for there to be IPv6 addresses that end in
  # f:3548 or 8:6144?  Yes, it is.  However, on the public network, we're
  # seeing addresses ending in the ...00:0000 to ...00:0fff range, so it will
  # be a long time before those last 16 bits tick over -- long enough, I hope,
  # that we won't have any more "stragglers" with IPv4 addresses and no IPv6
  # addresses by then.  And on the private network, I've been keeping the last
  # byte of the IPv6 address equal to the last byte of the IPv4 address, so no
  # collision can occur.

  # Historical Note: How we used to construct EUI-48 addresses:
  #
  # First, the type of VM determined the first 3 octets (and both VMware and
  # KVM suggest setting the 2 high bits of the 4th to 0).
  #
  # I would set the final two octets to be equal to the system's IPv4 address
  # on that interface, unless we were building a stemcell, in which case they
  # were zero, or we were installing from a stemcell and didn't know the final
  # IP address, in which case they were randomly generated, and we set a bit in
  # the 4th octet to indicate that they were randomly generated.
  #
  # I defined some of the bits in the 4th octet:
  # Bit 0: The final two octets are randomly generated
  # Bit 1: Public or private interface -- 0=public, 1=private
  # Bit 2: Building a stemcell (0=installing, 1=building)
  # Bit 3: Prevent automatic network configuration on boot (0=auto, 1=no)
  #
  # Bit 0 prevented hardware address collisions in case the final two randomly-generated
  # octets happened to be identical to two octets that were in use.
  #
  # Bit 1 prevented hardware address collisions in case the two last octets of the public IP
  # address happened to be equal to the last two octets of some existing
  # private IP address, and vice versa.
  #
  # Bit 2 prevented hardware address collisions in case the final two octets happened to be
  # equal to the stemcell ones (unlikely, as they were zero).
  #
  # Bit 3 didn't prevent hardware address collisions; it was just a signal and was unused
  # (and always zero) when rebuilding stemcell.  Later I had this script using
  # Guestfish to write network configuration directly to the new VM's disks, so
  # this became unnecessary.
  #
  # Old EUI-48 Diagram:
  #
  # Octets are numbered 11:22:33:44:55:66 below
  #
  # Octet 1, bits 7-0 \
  # Octet 2, bits 7-0  \
  # Octet 3, bits 7-0  / All of these defined by type of VM
  # Octet 4, bits 7-6 /
  # Octet 4, bits 5-4: Unused
  # Octet 4, bit 3: Auto net config? 1=no, 0=yes
  # Octet 4, bit 2: Rebuilding stemcell? 1=yes, 0=no
  # Octet 4, bit 1: Public interface? 1=yes/public, 0=no/private
  # Octet 4, bit 0: Next two octets randomly generated? 1=yes, 0=no/IP-based
  # Octet 5 \ If rebuilding stemcell, octet 5 is zero and octet 6 indicates the distro.
  # Octet 6 / If building a VM, last 2 octets of IPv4 address or randomly generated.
  #
  # Originally the hardware address was both the only way that this script
  # could communicate with the Cobbler server and tell it what to do, and also
  # the only way that this script could communicate with the newly-created VM.
  # Then other means became available.  We can now use Guestfish to write
  # arbitrary files on the guest's disk images before it boots, so much less is
  # needed here.  We still do need to set up the hardware address to tell
  # Cobbler what system record to use when PXE booting (in the case of
  # rebuilding a stemcell).

  my($vmname, $nic, $net) = @_;
  return '' unless(($nic eq 'public') || ($nic eq 'private'));

  # Array of hardware address bytes that we'll join to return.
  my(@hwa) = ();

  my %suffix = (
		'public' => 'grid.iu.edu',
		'private' => 'goc'
	       );

  # Special case if we're rebuilding a stemcell: the final octet denotes the
  # distro (the Cobbler server can be configured to have a system record for
  # each specific hardware address that directs it to auto-PXE-boot the appropriate
  # distro's stemcell installation profile).  If we add more distros, put them
  # here.  If the 128 bit is set, it means some strange variant of the distro
  # (the only one in use is 32-bit RHEL 5).
  my %stemcell_distro_indicator =
    (
     5 => 0,
     6 => 1,
     c6 => 2,
     c7 => 3,
    );

  my($short, $version) = split(/\./, $vmname, 2);
  # If there is no version in $vmname, just use $vmname.
  $short ||= $vmname;
  $version ||= 0;

  # VMware recommends 00:50:56:XX:YY:ZZ with XX between 0 and 0x3f.
  # KVM recommends 52:54:00:XX:YY:ZZ, also with XX between 0 and 0x3f.
  if($CFG::KVM) {
    push @hwa, (0x52, 0x54, 0);
  } else {
    push @hwa, (0, 0x50, 0x56);
  }
  if($CFG::CALLED_AS eq 'rebuild_stemcell') {
    my @last2 = (0, 0);
    # Rebuilding a stemcell: Turn on the stemcell-rebuild flag and set the last
    # octet to the code for the distro.
    push @hwa, 0x04;
    $last2[1] = $stemcell_distro_indicator{$CFG::DISTRO};
    if($CFG::ARCH eq 'x86') {
      # Turn on the "weird variant distro" indicator if we're using 32-bit RHEL
      # 5.
      $last2[1] |= 0x80;
    }
    if($nic eq 'private') {
      $hwa[3] |= 0x02;
    }
    push @hwa, @last2;
  } else { # We're installing a stemcell, not rebuilding one.
#    unless($CFG::AUTOINSTALL) {
#      $hwa[3] |= 0x08;
#    }
    my $hostname;
    if($net->{$nic}->{hostname}) {
      $hostname = $net->{$nic}->{hostname};
    } else {
      $hostname = sprintf('%s.%s', $short, $suffix{$nic});
    }
    # Last 20 bits of the $nic's IP
    my @ip_octets = ();
    # If we already have the IP, use it.  Use the IPv6, if any, in preference
    # to the IPv4.
    my $ip = $net->{$nic}->{ipv6} || $net->{$nic} ->{ipv4};
    # If we found an IP, use it; otherwise, generate 20 random bits.
    my $ip22;
    if($ip) {
      debug_printf 'Found %s; using it', $ip;
      $ip22 = Math::BigInt->new($ip->numeric);
      debug_printf 'Numerically, it is %s', $ip22->as_hex;
      # Mask the low 20 bits.
      $ip22 &= Math::BigInt->new('0xfffff');
    } else {
      debug_printf 'Found no IP; generating random bits';
      # Generate 20 random bits.
      $ip22 = Math::BigInt->new(makerandom(Size => 20, Strength => 1));
      # Set the 21st bit, to indicate that this number was randomly generated.
      # This will become the 22nd bit.
      $ip22 |= Math::BigInt->new('0x100000');
    }
    $ip22 <<= 1;
    # Set the low bit if this is the private interface.
    if($nic eq 'private') {
      $ip22 |= Math::BigInt->new('1');
    }
    # Add these three octets to @hwa.
    my @last3 = ();
    for(my $i = 0; $i < 3; $i++) {
      push @last3, (($ip22 >> 8*$i) & Math::BigInt->new('0xff'));
    }
    push @hwa, reverse(@last3);
  }
#    # What are the last two octets of the $nic's IP?
#    my @ip_octets = ();
#    # If we already have the IP, no problem.
#    if($net->{$nic}->{ip}) {
#      @ip_octets = split(/\./, $net->{$nic}->{ip});
#    } else {
#      # If we don't already have it, try to look it up.
#      my $pfxs = get_prefixes $nic, $hostname;
#      if(defined $pfxs) {
#	@ip_octets = unpack('C4', ${$h->addr_list}[0]);
#      } else {
#	# If we couldn't find it, print a warning.
#	carp (sprintf "Warning: Unable to resolve hostname '%s'", $hostname);
#      }
#    }
#    # Define the last 2 octets of the hardware address.
#    if(scalar(@ip_octets) > 0) {
#      # If @ip_octets was assigned above, use those values.
#      @last2 = @ip_octets[2, 3];
#    } else {
#      # If @ip_octets is empty, set the random bit and use random values.
#      $hwa[3] |= 0x01;
#      @last2 = (rand(256), rand(256));
#    }
#  }
#  if($nic eq 'private') {
#    $hwa[3] |= 0x02;
#  }
#  $hwa[4] = $last2[0];
#  $hwa[5] = $last2[1];
  return join(':', map { sprintf('%02X', $_) } @hwa);
}

sub determine_service($) {
  # Given the "short name" of the host, determine the name of the service, a
  # string that is acceptable as a value for the -s option to the install.sh
  # script.  Basically this should be the name of a subdirectory of the install
  # tree.  Returns the result.
  my($short) = @_;
  my $service = $short;
  # Remove any numbers from the end.
  $service =~ s/\d+$//;
  # Remove these suffixes from the end.
  unless($service eq 'puppet-test') {
    foreach my $ss (qw(-itb -dev -docteam -int -test)) {
      $service =~ s/\Q$ss\E$//;
    }
  }
  # Deal with special cases where this process doesn't return the service for
  # one reason or another.
  if($service eq 'backup') {
    $service = 'backup.grid';
  } elsif(($service eq 'adeximo') ||
	  ($service eq 'cpipes') ||
	  ($service eq 'echism') ||
	  ($service eq 'kagross') ||
	  ($service eq 'rquick') ||
	  ($service eq 'schmiecs')) {
    $service = 'supportvm';
  } elsif(($service eq 'soichi') ||
	  ($service eq 'steige') ||
	  ($service eq 'thomlee')) {
    $service = 'vanilla';
  }
  return $service;
}

sub determine_instance() {
  # Given the short hostname, determine the instance of the service that is to
  # be installed.  Typically this is just the short hostname plus
  # '.grid.iu.edu'.
  my($short) = @_;
  return($short.'.grid.iu.edu');
}

sub find_other_versions($) {
  # Given a VM name (that might or might not currently exist on the host), look
  # for other versions of the VM on the host and return a list of them.  By
  # convention the GOC uses ".<number>" to denote different versions of the
  # same VM.  This is because the part before the dot and number is identical
  # to the shortened hostname of the VM, and you can't have a dot within a
  # shortened hostname (or it wouldn't be a shortened hostname).
  my($vm) = @_;
  my($base, $version) = split(/\./, $vm);
  my @others = grep {
    $_->get_name() =~ /^\Q$base\E\./ and $_->get_name() ne $vm
  } $CFG::VMM->list_all_domains();
  return @others;
}

sub autostart_ask($) {
  # After a mkvm, rmvm, mvvm, cpvm, autovm, noautovm, or anything else that
  # might change the autostart status of a VM and/or whatever other versions of
  # it exist on the host, run a check to see if there's autostart trouble --
  # make sure that one and only one of its versions is set to autostart.  If
  # there's trouble, give the user an option about what to do, and do what they
  # choose.
  my($vm) = @_;

  # If we're here from an rmvm, the VM won't exist, but other versions of it
  # still might.  Get the domain object, if it exists, and get the others with
  # the same name but different versions, if they exist.
  my $dom = get_domain_by_name $vm;
  my @others = find_other_versions $vm;

  # Search through the domains we found for the ones that are set to autostart.
  # But first decide which ones to search.
  my @family = @others;
  push @family, $dom if defined $dom;
  @family = sort { $a->get_name() cmp $b->get_name() } @family;

  # OK, if @family is empty, we have no domains at all.  This probably means
  # that the user just used rmvm to delete the only domain in a "family," so
  # there's nothing to test.  If that's the case, just leave.
  return unless $#family > -1;

  # Now see which of these are set to autostart.
  my @autostarts = grep {
    $_->get_autostart();
  } (@family);

  # Now, if there isn't exactly one domain in this "family" set to autostart
  # (i.e. $#autostarts is not 0), we have one of two problems.
  return if $#autostarts == 0;		# Only one; not a problem

  # Either no domains in this "family" are set to autostart, or more than one
  # of them are.
  my($base, $version) = split(/\./, $family[0]->get_name());
  if($#autostarts == -1) {
    debug_printf 'No VM set to autostart.';
    # None of them are set to autostart.
    my $input = undef;
    if($CFG::YES) {
      # A -y on the command line means we can't ask the user because we're
      # probably in a script. Do the most logical thing and set the VM with the
      # highest version number to autostart.
      debug_printf 'Autoselecting highest version.';
      my $maxversion = $version;
      my $count = 1;
      foreach my $d (@family) {
	my($db, $dv) = split(/\./, $d->get_name());
	if($dv > $maxversion) {
	  $maxversion = $dv;
	  $input = $count;
	}
	$count++;
      }
    } else {
      # Ask the user what to do.
      printf "No VM with basename '%s' is set to autostart.\n", $base;
      until(defined $input) {
	my $count = 1;
	foreach my $d (@family) {
	  printf "%2d) %s\n", $count++, $d->get_name();
	}
	print "Enter a number to select one to set to autostart, or enter 0 to do nothing.\n";
	print "Your choice: ";
	$input = <STDIN>;
	chomp $input;
	if($input !~ /^\d+$/ or $input > ($#family + 1)) {
	  printf "Please enter a number between 0 and %d.\n", $#family + 1;
	  $input = undef;
	}
      }
    }
    if($input == 0) {
      print "Doing nothing.\n";
    } else {
      printf "Setting VM '%s' to autostart.\n", $family[$input - 1]->get_name();
      $family[$input - 1]->set_autostart(1);
    }
  } else {
    # More than one of them are set to autostart.
    my $input = undef;
    if($CFG::YES) {
      my $maxversion = $version;
      my $count = 1;
      foreach my $d (@family) {
	my($db, $dv) = split(/\./, $d->get_name());
	if($dv > $maxversion) {
	  $maxversion = $dv;
	  $input = $count;
	}
	$count++;
      }
    } else {
      # Ask the user what to do.
      printf "More than one VM with basename '%s' is set to autostart.\n", $base;
      until(defined $input) {
	my $count = 1;
	foreach my $d (@family) {
	  printf "%2d) %s%s\n", $count++, $d->get_name(),
	    ($d->get_autostart()?' (auto)':'');
	}
	print "Enter a number to select one to set to autostart, or enter 0 to do nothing.\n";
	print "Your choice: ";
	$input = <STDIN>;
	chomp $input;
	if($input !~ /^\d+$/ or $input > ($#family + 1)) {
	  printf "Please enter a number between 0 and %d.\n", $#family + 1;
	  $input = undef;
	}
      }
    }
    if($input == 0) {
      print "Doing nothing.\n";
    } else {
      printf "Only VM '%s' will be set to autostart.\n",
	$family[$input - 1]->get_name();
      # Set them all to not autostart, then just set the selected one.
      foreach my $d (@family) {
	$d->set_autostart(0);
      }
      $family[$input - 1]->set_autostart(1);
    }
  }
}

sub generate_uuid($) {
  # Given a VM name, generate a UUID.
  my($vmname) = @_;
  tie my $u, 'OSSP::uuid::tie';
  my $dn = sprintf('CN=%s,OU=VMs,DC=goc', $vmname);
  $u = [ 'v3', 'ns:X500', $dn ];
  my $uuid = sprintf('%s', $u);
  untie $u;
  return $uuid;
}

sub guestfs_mount_all(\%) {
  # Mount all filesystems that Sys::Guestfs can find.  I don't understand why
  # Sys::Guestfs doesn't automatically do this after a call to the launch()
  # method, since guestfish automatically mounts all the filesystems.  But not
  # only doesn't Sys::Guestfs do this automatically, it doesn't even have a
  # method you can call to do it.  That's disappointing.  There is a
  # umount_all() method.
  my($g) = @_;
  my $root;
  try {
    $root = $g->inspect_os;
  };
  unless($@ eq '') {
    carp "Unable to inspect guest: $@";
  }
  my @fs;
  try {
    @fs = $g->inspect_get_filesystems($root);
  };
  unless($@ eq '') {
    carp "Unable to get list of filesystems on guest: $@";
  }
  my %mp;
  try {
    %mp = reverse $g->inspect_get_mountpoints($root);
  };
  unless($@ eq '') {
    carp "Unable to get list of filesystem mountpoints on guest: $@";
  }
  foreach my $fs (@fs) {
    next unless $mp{$fs}; # @fs may contain swaps, but %mp never will
    try {
      $g->mount($fs, $mp{$fs});
    };
    unless($@ eq '') {
      carp "Unable to mount filesystem $fs on mount point $mp{$fs}: $@";
    }
  }
}

sub getips($) {
  # Given a hostname (FQDN), use libnss to look up its IP address(es),
  # returning them as a reference to an hash containing NetAddr::IP objects.
  # Returns undef if there's an error.  Returns a reference to an empty hash
  # if there are internal errors.
  #
  # The returned hash looks like this:
  #
  # {
  #   ipv4 => [ <NetAddr::IP object>, ... ],
  #   ipv6 => [ <NetAddr::IP object>, ... ],
  # }

  my($h) = @_;
  my($err, @res) = getaddrinfo($h, '', {socktype => SOCK_RAW});
  if($err) {
    carp (sprintf "Unable to resolve hostname %s: %s\n", $h, $err);
    return undef;
  }
  my %ips = ();
  foreach my $rec (@res) {
    if($rec->{addr}) {
      my(undef, $ipaddr) = getnameinfo $rec->{addr}, NI_NUMERICHOST;
      my $ip = NetAddr::IP->new($ipaddr);
      if(defined $ip) {
	my $version = sprintf 'ipv%d', $ip->version;
	push @{$ips{$version}}, $ip;
      } else {
	warn "IP address invalid: %s\n", $ipaddr;
	next;
      }
    } else {
      warn "Undefined IP address\n";
      next;
    }
  }
  return \%ips;
}

sub getprefixes($) {
  # Given a NIC code such as that used by lookup_network_params and
  # construct_hw_address (i.e. 'public' or 'private') and a hostname (FQDN),
  # use libnss to look up that hostname's IP address(es), returning them as a
  # reference to a hash of NetAddr::IP objects representing their prefixes (IP
  # address and bit mask).  Returns undef if there's an error.
  #
  # The returned hash looks like this:
  #
  # {
  #    ipv4 => <NetAddr::IP object>,
  #    ipv6 => <NetAddr::IP object>,
  # }

  my($nic, $h) = @_;
  my $ips = getips $h;
  return undef unless defined $ips;
  my %pfxs = ();
  foreach my $version (keys (%$ips)) {
    foreach my $ip (@{$ips->{$version}}) {
      # I don't know why it wouldn't be, but only save the IP if it's within
      # the VLAN in question's IP range.
      my $netpfx = $main::VLANDATA{$nic}->{prefix}->{$version};
      if($ip->within($netpfx)) {
	# Use the address from getips with the mask from %main::VLANDATA.
	my $pfx = NetAddr::IP->new(ip_canonical($ip), $netpfx->masklen);
	$pfxs{$version} = $pfx;
	# Only save the first one.
	last;
      }
    }
  }
  return \%pfxs;
}

sub lookup_network_params($) {
  # Given the VM name and some assumptions that the VM follows GOC network
  # conventions, figure out the network parameters for both network interfaces.
  # Mostly used by mkvm and rebuild_stemcell.  Returns a reference to a data
  # structure that looks like this:

  # {
  #   service => <service>,
  #   instance => <instance>,
  #   public => {
  #     hostname => <public hostname>,
  #     ipv4 => <NetAddr::IP object for public IPv4 address>,
  #     ipv6 => <NetAddr::IP object for public IPv6 address>,
  #     hwaddr => <public hardware address>,
  #   },
  #   private => {
  #     hostname => <private hostname>,
  #     ipv4 => <NetAddr::IP object for private IPv4 address>,
  #     ipv6 => <NetAddr::IP object for private IPv6 address>,
  #     hwaddr => <private hardware address>,
  #   },
  # }

  my($vmname) = @_;
  my @nics = qw(public private);
  my %suffix =
    (
     'public' => 'grid.iu.edu',
     'private' => 'goc'
    );
  my %data = ();
  my($short, $version) = split(/\./, $vmname, 2);
  # If there is no version in $vmname, set $version to 0 and just use $vmname
  # as is.
  $short ||= $vmname;
  $version ||= 0;
  foreach my $nic (@nics) {
    my $hostname = sprintf('%s.%s', $short, $suffix{$nic});
    $data{$nic}->{hostname} = $hostname;
    my $ip = &getprefixes($nic, $hostname);
    if($ip) {
      foreach my $version (keys(%$ip)) {
	if($ip->{$version}) {
	  debug_printf "Found %s %s address for '%s': %s/%s", $nic, $version, $hostname,
	    $ip->{$version}->short, $ip->{$version}->masklen;
	  $data{$nic}->{$version} = $ip->{$version};
	} else {
	  debug_printf "No %s %s address for '%s'", $nic, $version, $hostname;
	}
      }
    } else {
      # If the hostname is not found in DNS, complain.  The hardware address will be
      # random and won't transmit any useful information.
      warn (sprintf "Warning: Hostname '%s' not found in DNS.\n", $hostname);
    }
    my $hwaddr = &construct_hw_address($vmname, $nic, \%data);
    $data{$nic}->{hwaddr} = $hwaddr;
    debug_printf "Using hardware address '%s'.", $hwaddr;
  }
  my $service = &determine_service($short);
  $data{service} = $service;
  my $instance = &determine_instance($short);
  $data{instance} = $instance;
  if($CFG::AUTOINSTALL) {
    debug_printf "Using service '%s', instance '%s'", $service, $instance;
  }
  return \%data;
}

sub read_temp_gocvm_file($) {
  # Reads the given file as if it were a mkvm.pl file of the sort written by
  # make_temp_gocvm_file().  Returns a reference to a hash containing the data
  # in the format in which it is given to make_temp_gocvm_file.
  our($file) = @_;
  our $err = '';
  our %d = ();
  {
    package TMP;
    our($AUTOINSTALL, $NOAUTONET, $SERVICE, $INSTANCE, $REBUILDING, $DISTRO,
	$DISTV, $DISTSUBV, $DISTMINV, $SUGGEST_GATEWAY, %SUGGEST_HOSTNAME,
	%SUGGEST_IP, %SUGGEST_MASK, %SUGGEST_IPV6);
    my $return = do($file);
    if($@) {
      $::err = "Unable to compile $file: $@";
    } elsif(!defined($return)) {
      $::err = "Unable to read $file: $!";
    } elsif(!$return) {
      $::err = "Unable to process $file";
    }
    if($::err) {
      carp("$::err");
      return undef;
    }
    $::d{autoinstall} = $AUTOINSTALL?1:'';
    ::debug_printf "From mkvm.pl file: \$NOAUTONET = '%s'", defined($NOAUTONET)?$NOAUTONET:'(undef)';
    $::d{noautonet} = $NOAUTONET?1:'';
    $::d{called_as} = $REBUILDING?'rebuild_stemcell':'';
    ::debug_printf "From mkvm.pl file: \$DISTRO = '%s'", defined($DISTRO)?$DISTRO:'(undef)';
    ::debug_printf "From mkvm.pl file: \$DISTV = '%s'", defined($DISTV)?$DISTV:'(undef)';
    $::d{distro} = '6'; # So it doesn't have an undefined value
    # Change this if we add more distros
#    if(defined($DISTRO) && ($DISTRO eq 'RHEL')) {
#      $::d{distro} = $DISTV || '';
#    }
    $::d{net}->{service} = $SERVICE;
    $::d{net}->{instance} = $INSTANCE;
    $::d{net}->{public}->{ipv4} = NetAddr::IP->new("$SUGGEST_IP{eth0}/$SUGGEST_MASK{eth0}");
    $::d{net}->{private}->{ipv4} = NetAddr::IP->new("$SUGGEST_IP{eth1}/$SUGGEST_MASK{eth1}");
    $::d{net}->{public}->{ipv6} = NetAddr::IP->new("$SUGGEST_IPV6{eth0}");
    $::d{net}->{private}->{ipv6} = NetAddr::IP->new("$SUGGEST_IPV6{eth1}");
  }
  debug_printf "After reading mkvm.pl file: noautonet = '%s'", defined($d{noautonet})?$d{noautonet}:'(undef)';
  debug_printf "After reading mkvm.pl file: distro = '%s'", defined($d{distro})?$d{distro}:'(undef)';
  return \%d;
}

sub make_temp_gocvm_file(%) {
  # Creates the /opt/etc/gocvm/mkvm.pl file.  Well, actually it creates a
  # File::Temp object pointed at a temporary file that contains the text of the
  # mkvm.pl file, which the calling routine can then do whatever it wants with.
  # Usually this involves using Sys::Guestfs to put the file on the guest's
  # hard drive.

  # Call this routine with a hash of parameters:
  # net => reference to network parameters of the sort returned by lookup_network_params()
  # autoinstall => flag: automatically run install on first boot?
  # noautonet => flag: don't automatically set up network parameters on first boot?
  # called_as => command this script was called as (mkvm, rebuild_stemcell, etc.)
  # distro => distro code (5 = RHEL 5, 6 = RHEL 6, etc.; see %main::DISTRONAME)
  my %params = @_;
  my $tplfh = File::Temp->new(TEMPLATE => 'vmtoolXXXXXX',
			      DIR => '/tmp',
			      SUFFIX => '.pl');
  return undef unless $tplfh;
  my $thishost = hostname;
  unless(defined $thishost and $thishost ne '') {
    carp "(WARNING) Cannot determine current server hostname"
  }
  chomp $thishost if $thishost;
  my @hostparts = split(/\./, $thishost, 2);
  my $ts = time();
  my $lt = localtime($ts);
  my $gt = gmtime($ts);
  $tplfh->printf(<<"EOF");
# mkvm.pl -- System configuration information in Perl-readable format
# Written by vmtool when VM created; editing by hand not recommended
# Time this was written:
# Unix timestamp: $ts
# UTC: $gt
# Local time: $lt

EOF
    ;
  $tplfh->printf("# Unix timestamp when this file was written:\n\$CONFIG_TIMESTAMP = %d;\n\n", $ts);
  $tplfh->printf("# VM host:\n\$VMHOST = '%s';\n\n", $hostparts[0]);
  $tplfh->printf("# If this is 1, /opt/sbin/gocvminsta.pl will (when implemented) run the install script:\n\$AUTOINSTALL = '%s';\n\n", $params{autoinstall}?'1':'');
  $tplfh->printf("# The service to autoinstall:\n\$SERVICE = '%s';\n\n", $params{net}->{service});
  $tplfh->printf("# The instance of the service to autoinstall:\n\$INSTANCE = '%s';\n\n", $params{net}->{instance});
  $tplfh->printf("# If this is 1, /opt/sbin/gocvminsta.pl will set up networking parameters unless an install script has been run:\n\$NOAUTONET = '%s';\n\n", $params{noautonet}?'1':'');
  $tplfh->printf("# If this is 1, we're rebuilding a stemcell:\n\$REBUILDING = '%s';\n\n", ($params{called_as} eq 'rebuild_stemcell')?'1':'');
  # If $params{distro} is a number, it's a RHEL major version.
  if($params{distro} =~ /^\d+$/) {
    $tplfh->print("# The Linux distribution that was installed:\n\$DISTRO = 'RHEL';\n\n");
    $tplfh->printf("# The major version of the distro:\n\$DISTV = '%s';\n\n", $params{distro});
    $tplfh->print("# The subversion of the distro:\n\$DISTSUBV = '';\n\n");
    $tplfh->print("# The minor version of the distro:\n\$DISTMINV = '';\n\n");
  } elsif($params{distro} =~ /^c\d+$/i) {
    # If the first character of $params{distro} is 'c', it's CentOS, and the
    # rest is the major version.
    $tplfh->print("# The Linux distribution that was installed:\n\$DISTRO = 'CentOS';\n\n");
    my($v) = ($params{distro} =~ (/^c(\d+)$/));
    $tplfh->printf("# The major version of the distro:\n\$DISTV = '%s';\n\n", $v);
    $tplfh->print("# The subversion of the distro:\n\$DISTSUBV = '';\n\n");
    $tplfh->print("# The minor version of the distro:\n\$DISTMINV = '';\n\n");
  } else {
    $tplfh->print("# The Linux distribution that was installed:\n\$DISTRO = '';\n\n");
    $tplfh->print("# The major version of the distro:\n\$DISTV = '';\n\n");
    $tplfh->print("# The subversion of the distro:\n\$DISTSUBV = '';\n\n");
    $tplfh->print("# The minor version of the distro:\n\$DISTMINV = '';\n\n");
  }
  my $randomhwaddrs;
  if($params{net}->{public}->{ipv4} or $params{net}->{public}->{ipv6}) {
    $randomhwaddrs = ''
  } else {
    $randomhwaddrs = 1;
  }
  $tplfh->printf("# If this is 1, the virtual NICs were assigned random hardware addresses:\n\$RANDOMHWADDRS = '%s';\n\n", $randomhwaddrs);
  $tplfh->printf("# Suggested network parameters for the virtual NICs:\n%%SUGGEST_IP = ('eth0' => '%s', 'eth1' => '%s');\n",
		 map { $params{net}->{$_}->{ipv4}?ip_canonical($params{net}->{$_}->{ipv4}):'' } (qw(public private)));
  $tplfh->printf("%%SUGGEST_MASK = ('eth0' => '%s', 'eth1' => '%s');\n",
		 map { $params{net}->{$_}->{ipv4}?$params{net}->{$_}->{ipv4}->mask:'' } (qw(public private)));
  $tplfh->printf("\$SUGGEST_GATEWAY = '%s';\n",
		 $main::VLANDATA{public}->{gateway}->{ipv4});
  $tplfh->printf("\$SUGGEST_IPV6 = ('eth0' => '%s', 'eth1' => '%s');\n",
		 map { $params{net}->{$_}->{ipv6}?ip_canonical($params{net}->{$_}->{ipv6}, 1):'' } (qw(public private)));
  $tplfh->printf("\$SUGGEST_GATEWAY_IPV6 = '%s%%%s';\n",
		 $main::VLANDATA{public}->{gateway}->{ipv6},
		 $main::VLANDATA{public}->{intf});
  $tplfh->printf("%%SUGGEST_HOSTNAME = ('eth0' => '%s', 'eth1' => '%s');\n",
		 $params{net}->{public}->{hostname}, $params{net}->{private}->{hostname});
  $tplfh->flush();
  return $tplfh;
}

sub aug_set_protect($$$) {
  # When Sys::Guestfs::Augeas gets an error (amazingly including "No error",
  # which indicates an unusual but not fatal condition), it totally bombs out
  # of the entire script, so we always have to be very careful, doing aug_set
  # within a try and checking $@ when done for errors. This routine takes an
  # initialized Sys::Guestfs object, a key, and a value to set. It attempts to
  # set this value. If there's an error, it will print a message to stderr and
  # return undef. Returns 1 on success.
  my($g, $key, $value) = @_;
  unless(defined $key) {
    carp "aug_set_protect called with undefined key";
    return undef;
  }
  unless(defined $value) {
    carp "Undefined value for key '$key' passed to aug_set_protect";
    return undef;
  }
  try {
    $g->aug_set($key, $value);
  };
  unless($@ eq '') {
    carp "aug_set failed (key '$key'): $@";
    return undef;
  }
  return 1;
}

sub aug_get_protect($$) {
  # When Sys::Guestfs::Augeas get an error, it totally bombs out of the entire
  # script, so we always have to be very careful, checking aug_match before
  # doing an aug_get to make sure the key actually exists.  This routine takes
  # an initialized Sys::Guestfs object and a key whose value we want to
  # retrieve.  If the key doesn't exist, returns undef.  If the key exists,
  # returns its value.  The value might still be '', which still evaluates to
  # false in Perl, so watch out for that.
  my($g, $key) = @_;
  unless(defined $key) {
    carp "aug_get_protect called with undefined key";
    return undef;
  }
  my $value = undef;
  try {
    $value = $g->aug_match($key);
  };
  unless($@ eq '') {
    carp "Unable to get key '$key': $@";
    return undef;
  }
  return $value;
}

sub guestfs_set_net_parameters(\%\%) {
  # Given a Sys::Guestfs object that has been launched on a domain and its
  # drives mounted, and a network information hashref of the sort returned by
  # lookup_network_params(), write the changes to the guest system's drive.

  my($g, $net) = @_;
  print "Setting network parameters ...\n";
  my %old_hostname = ();
  my %oldip = ();
  # We're going to use Augeas for this, so initialize it.
  try {
    $g->aug_init("/", 0);
  };
  unless($@ eq '') {
    carp "Unable to initialize Augeas: $@";
    return undef;
  }
  # Augeas makes the settings within config files look like they're part of a
  # filesystem. aug_defvar allows us to set a shortcut for the purposes of this
  # path, but be careful not to allow Perl to try to evaluate this shortcut,
  # since it begins with $ just like a Perl variable -- put it in single quotes
  # or escape the $ if in double quotes.
  try {
    $g->aug_defvar('nw', '/files/etc/sysconfig/network');
  };
  $old_hostname{public} = aug_get_protect $g, '$nw/HOSTNAME';
  debug_printf "Old hostname from /etc/sysconfig/network: %s", $old_hostname{public};
  # /etc/sysconfig/network must have HOSTNAME=<external hostname> and
  # GATEWAY=<gateway>.  And NETWORKING=yes if there's networking.  Also, if
  # there's IPv6, NETWORKING_IPV6=yes, and
  # IPV6_DEFAULTGW=<gateway>%<interface>.
  if($net->{public}->{ipv4} or $net->{public}->{ipv6}
     or $net->{private}->{ipv4} or $net->{private}->{ipv6}) {
    aug_set_protect $g, '$nw/NETWORKING', 'yes';
  } else {
    aug_set_protect $g, '$nw/NETWORKING', 'no';
  }
  aug_set_protect $g, '$nw/HOSTNAME', $net->{public}->{hostname};
  if($net->{public}->{ipv4}) {
    aug_set_protect $g, '$nw/GATEWAY', $main::VLANDATA{public}->{gateway}->{ipv4};
  }
  if($net->{public}->{ipv6} or $net->{private}->{ipv6}) {
    aug_set_protect $g, '$nw/NETWORKING_IPV6', 'yes';
  } else {
    aug_set_protect $g, '$nw/NETWORKING_IPV6', 'no';
  }
  if($net->{public}->{ipv6}) {
    aug_set_protect $g,
      '$nw/IPV6_DEFAULTGW',
      $main::VLANDATA{public}->{gateway}->{ipv6}.'%'.$main::VLANDATA{public}->{intf};
  }

  # If this is a RHEL/CentOS 7 installation, the HOSTNAME setting isn't found
  # in /etc/sysconfig/network but in /etc/hostname instead.  Not that it hurts
  # for it to be in /etc/sysconfig/network, but it's ignored.
  unless($CFG::DISTRO eq '5' or $CFG::DISTRO eq '6' or $CFG::DISTRO eq 'c6') {
    aug_set_protect $g, '/files/etc/hostname/hostname', $net->{public}->{hostname};
  }

  # The IPs, netmasks, and hardware addresses must be in the network scripts
  # files.
  foreach my $version (qw(ipv4 ipv6)) {
    foreach my $nic (qw(public private)) {
      try {
	$g->aug_defvar('ifc',
		       '/files/etc/sysconfig/network-scripts/ifcfg-'.$main::VLANDATA{$nic}->{intf});
      };
      aug_set_protect $g, '$ifc/HWADDR', $net->{$nic}->{hwaddr};
      aug_set_protect $g, '$ifc/BOOTPROTO', 'none';
      if($version eq 'ipv4') {
	my $ip = aug_get_protect $g, '$ifc/IPADDR';
	$oldip{$nic}->{$version} = $ip if defined $ip;
	if($net->{$nic}->{$version}) {
	  aug_set_protect $g, '$ifc/IPADDR', $net->{$nic}->{$version}->addr;
	  aug_set_protect $g, '$ifc/NETMASK', $net->{$nic}->{$version}->mask;
	}
      } elsif($version eq 'ipv6') {
	my $ip = aug_get_protect $g, '$ifc/IPV6ADDR';
	$oldip{$nic}->{$version} = $ip if defined $ip;
	if($oldip{$nic}->{$version}) {
	  ($oldip{$nic}->{$version}) = split('/', $oldip{$nic}->{$version}, 2);
	}
	if($net->{$nic}->{$version}) {
	  aug_set_protect $g, '$ifc/IPV6INIT', 'yes';
	  aug_set_protect $g, '$ifc/IPV6ADDR', ip_canonical($net->{$nic}->{$version}, 1);
	} else {
	  aug_set_protect $g, '$ifc/IPV6INIT', 'no';
	}
      } else {
	carp "Shouldn't be here: \$version ('$version') is neither 'ipv4' nor 'ipv6'";
      }
      if(defined $oldip{$nic}->{$version}) {
	debug_printf "Old %s %s address: %s", $nic, $version, $oldip{$nic}->{$version};
      } else {
	debug_printf "%s had no %s %s address\n", $main::VLANDATA{$nic}->{intf}, $nic, $version;;
      }
    }
  }

  try {
    $g->aug_defvar('hosts', '/files/etc/hosts');
  };
  # Make sure /etc/hosts has the external hostname/IP. The /etc/hosts file is
  # treated a bit unusually in Augeas, because its data doesn't have labels,
  # because it can have an arbitrary number of records, and because each record
  # may have an arbitrary number of hostnames. It looks like this:
  #
  # /files/etc/hosts/1/ipaddr = '127.0.0.1'
  # /files/etc/hosts/1/canonical = 'localhost'
  # /files/etc/hosts/1/alias[1] = 'localhost.localdomain'
  # /files/etc/hosts/1/alias[2] = 'lh'
  #
  # As you can see, the records are just labeled with numbers, starting with 1.
  # Each record has an 'ipaddr' label and a 'canonical' label (the first
  # hostname). Other hostnames, if any, appear as the multivalued 'alias'
  # label, working like an array whose first index is 1.

  foreach my $version (qw(ipv4 ipv6)) {
    # Skip this if there is no ipv4/ipv6 address.
    next unless exists $net->{public}->{$version};
    # First, look for a line with the old public IP. If there was one, change
    # it. If there wasn't, test onward.
    my $nnodes;
    try {
      $nnodes = $g->aug_defvar('oh',
			       (sprintf '$hosts/*[ipaddr="%s"]',
				$oldip{public}->{$version}));
    };
    if($nnodes) {
      debug_printf "Old %s found in /etc/hosts; changing to new one", $version;
      aug_set_protect $g, '$oh/ipaddr', ip_canonical($net->{public}->{$version});
      aug_set_protect $g, '$oh/canonical', $net->{public}->{hostname};
      $g->aug_rm('$oh/alias');
    } else {
      # The old IP didn't appear -- strange!  See if the new IP does for some reason.
      if($g->aug_defvar('nh', sprintf('$hosts/*[ipaddr="%s"]',
				      ip_canonical($net->{public}->{$version})))) {
	debug_printf "New %s found in /etc/hosts (somewhat odd, but OK)", $version;
	# The new IP is there -- see if the hostname appears somewhere.  If it
	# does, leave it alone.
	unless(($g->aug_get('$nh/canonical') eq $net->{public}->{hostname})
	       || ($g->aug_get(sprintf('$nh/alias[.="%s"]', $net->{public}->{hostname})))) {
	  debug_printf "New hostname not found in /etc/hosts (slightly more odd; fixing)";
	  # The hostname doesn't appear anywhere on the line.  Add it to the
	  # aliases, at least.
	  aug_set_protect $g, '$nh/alias[last()+1]', $net->{public}->{hostname};
	}
      } else {
	debug_printf "Neither old nor new %s found in /etc/hosts; adding new IP", $version;
	# Neither the old nor the new IP appears.  Create a new record for the
	# new IP and hostname.
	# NOTE: Somehow this returned no values on oasis.grid on 2014-03-11
	my @hosts = sort $g->aug_match('$hosts/*[ipaddr]');
	my($lasthost, $lastnum);
	if(@hosts) {
	  $lasthost = $hosts[$#hosts];
	  ($lastnum) = ($lasthost =~ /(\d+)$/);
	} else {
	  $lasthost = '';
	  $lastnum = 0;
	}
	# That's got the label for the last record -- create one with
	# $lastnum + 1.
	$g->aug_defnode('new', sprintf('$hosts/%d', $lastnum + 1), '');
	aug_set_protect $g, '$new/ipaddr', ip_canonical($net->{public}->{$version});
	aug_set_protect $g, '$new/canonical', $net->{public}->{hostname};
      }
    }
  }

  try {
    $g->aug_save;
  };
  unless($@ eq '') {
    carp "aug_save failed: $@";
    return undef;
  }
  try {
    $g->aug_close;
  };
  unless($@ eq '') {
    carp "aug_close failed: $@";
    return undef;
  }
  return 1;
}

sub guestfs_sign_ssh_key(\%\%$) {
  # Given a launched Sys::Guestfs object with a domain added and drives
  # mounted, a reference to a hash of the sort returned by
  # lookup_network_params(), and a temporary directory, get the cert server to
  # sign the KVM domain's SSH host key.  If it doesn't have a key, try to
  # create one.

  # Obviously this requires a few things:
  # * There must be a cert.grid.iu.edu server with /opt/sbin/signhostkey on it.
  # There must be a 'goc' user on it, and the signhostkey script's permissions
  # must be such that the 'goc' user can run it.
  # * /root/.ssh/id_goc.dsa must contain the SSH key necessary to connect as
  # that 'goc' user.

  # Returns 1 on success, undef on failure.
  my($g, $net, $dir) = @_;
  print "Creating SSH certificate ...\n";
  my $shrkp = 'ssh_host_rsa_key.pub';
  my $skp = "/etc/ssh/$shrkp";
  if($g->is_file($skp)) {
    try {
      $g->download("/etc/ssh/ssh_host_rsa_key.pub", "$dir/ssh_host_rsa_key.pub");
    };
    unless($@ eq '') {
      carp "Sys::Guestfs unable to download $skp: $@";
      return undef;
    }
  } else {
    warn "guestfs_sign_ssh_key is unable to find a key at $skp.  Creating one if possible ...\n";
    # This would be very odd, but if it exists and is not a regular file, move
    # it aside.  If something exists at $skp.bak, it is out of luck.
    if($g->exists($skp)) {
      try {
	$g->rm_rf("$skp.bak");
      };
      unless($@ eq '') {
	carp "Sys::Guestfs unable to delete $skp.bak: $@";
	return undef;
      }
      try {
	$g->mv($skp, "$skp.bak");
      };
      unless($@ eq '') {
	carp "Sys::Guestfs unable to rename $skp to $skp.bak: $@";
	return undef;
      }
    }
    # Now that we're sure nothing exists at $skp, create an SSH key so there's
    # something to have signed.
    if(system("ssh-keygen -q -t rsa -b 2048 -f $dir/$shrkp -N ''") >> 8) {
      carp "Unable to create 2048-bit RSA key at $dir/$shrkp: $!";
      return undef;
    }
    # And put it on the guest filesystem.
    try {
      $g->upload("$dir/$shrkp", $skp);
    };
    unless($@ eq '') {
      carp "Sys::Guestfs unable to upload $skp: $@";
      return undef;
    }
  }
  my $ip = $net->{public}->{ipv6} || $net->{public}->{ipv4};
  my $ipaddr = ip_canonical($ip);
  # There is definitely a key now, so have it signed.
  if(system("cat $dir/$shrkp | ssh -i /root/.ssh/id_goc.dsa goc\@cert.grid.iu.edu /opt/sbin/signhostkey -i '$ipaddr' > $dir/ssh_host_rsa_key-cert.pub") >> 8) {
    carp "Unable to sign $dir/$shrkp: $!";
    return undef;
  }
  # And put the new certificate on the guest filesystem.
  try {
    $g->upload("$dir/ssh_host_rsa_key-cert.pub", "/etc/ssh/ssh_host_rsa_key-cert.pub");
  };
  unless($@ eq '') {
    carp "Sys::Guestfs unable to upload /etc/ssh/ssh_host_rsa_key-cert.pub: $@";
    return undef;
  }
  return 1;
}

sub guestfs_get_id_from_file {
  # Given a launched Sys::Guestfs object with a domain added and drives
  # mounted, the path to an ID file to download from the guest and search
  # (typically '/etc/passwd' or '/etc/group'), a name to search for (usually a
  # username or group name), and a temporary directory to save the file in,
  # this will search the file in question for an entity named $name and return
  # its ID number (UID or GID).  For example, if you were searching /etc/group
  # for a group named 'puppet', you would do this (with $g being the
  # Sys::Guestfs object and $dir being the path to the temporary directory):

  # $gid = &guestfs_get_id_from_file($g, '/etc/group', 'puppet', $dir);

  #Returns undef if the file wasn't found or if $name wasn't found in it.
  my($g, $file, $name, $dir) = @_;
  if($g->exists($file) && $g->is_file($file)) {
    try {
      $g->download($file, "$dir/tempidfile");
    };
    unless($@ eq '') {
      carp "Sys::Guestfs unable to download $file: $@";
    }
  }
  my $fh = IO::File->new("<$dir/tempidfile");
  unless($fh) {
    carp "Unable to open $dir/tempidfile for reading: $!";
    return undef;
  }
  my $id = undef;
  if($fh) {
    my $line;
    while(defined($line = <$fh>)) {
      chomp($line);
      next unless substr($line, 0, length($name) + 1) eq "$name:";
      (undef, undef, $id, undef) = split(/:/, $line, 4);
      last;
    }
    $fh->close();
  }
  return $id;
}

sub guestfs_create_sign_puppet_cert(\%\%$) {
  # Given a launched Sys::Guestfs object with a domain added and drives
  # mounted, a reference to a hash of the sort returned by
  # lookup_network_params, and a temporary directory, get the domain set up to
  # use Puppet.  This means creating a private key and certificate request for
  # the domain's public hostname, sending it to the Puppet server to get it
  # signed, and putting the certificate thus obtained along with the private
  # key in their proper places within the domain's filesystem.  Returns 1 if
  # everything was successful, '' if there was a problem, and undef if the
  # subroutine couldn't run because Puppet isn't installed on the guest, or is
  # installed unusually.
  my($g, $net, $dir) = @_;
  print "Creating and installing Puppet certificate ...\n";
  my $status;
  # First make sure Puppet is actually installed on the guest system.  It
  # usually is, but if for some reason it isn't, there's no point in continuing
  # with this subroutine.  If there's no /etc/puppet directory, assume Puppet
  # isn't installed.
  unless($g->is_dir('/etc/puppet')) {
    carp "/etc/puppet does not exist or is not a directory -- not creating Puppet cert";
    return undef;
  }
  # If the directories in which we're going to install the cert and key don't
  # exist, there's also no point in continuing with this.
  unless($g->is_dir('/etc/puppet/ssl')) {
    carp "/etc/puppet/ssl does not exist or is not a directory -- not creating Puppet cert";
    return undef;
  }
  unless($g->is_dir('/etc/puppet/ssl/private_keys')) {
    carp "/etc/puppet/ssl/private_keys does not exist or is not a directory -- not creating Puppet cert";
    return undef;
  }
  unless($g->is_dir('/etc/puppet/ssl/certs')) {
    carp "/etc/puppet/ssl/certs does not exist or is not a directory -- not creating Puppet cert";
    return undef;
  }
  # Get the hostname -- it goes in the filenames of the cert and its key.
  my $h = $net->{public}->{hostname};
  # Create the private key and CSR
  $status = system("openssl req -new -sha256 -nodes -newkey rsa:2048 -subj '/CN=$h' -keyout $dir/$h-key.pem -out $dir/$h-csr.pem >& /dev/null") >> 8;
  if($status != 0) {
    carp "Unable to generate a certificate: $!";
    return '';
  }
  # Give the CSR to the Puppet server to sign
  $status = system("cat $dir/$h-csr.pem | ssh -i /root/.ssh/id_goc.dsa puppetcert\@puppet.grid.iu.edu sudo -n -E /opt/sbin/puppet-deletecert -s $h > $dir/$h-cert.pem");
  if($status != 0) {
    carp "Unable to get certificate signed: $!";
    return '';
  }
  # Put the cert and the private key where they belong. Incidentally, if you're
  # wondering why I'm executing these Sys::Guestfs calls within try statements,
  # it's because in their infinite wisdom the writers of that module decided to
  # have every single error call croak (see the Carp module), meaning the
  # entire script would die. We'd never get to check the return status because
  # the script would have exited by then.
  try {
    $g->upload("$dir/$h-key.pem", "/etc/puppet/ssl/private_keys/$h.pem");
  };
  unless($@ eq '') {
    carp "Key file upload failed: $@";
    return '';
  }
  try {
    $g->upload("$dir/$h-cert.pem", "/etc/puppet/ssl/certs/$h.pem");
  };
  unless($@ eq '') {
    carp "Cert file upload failed: $@";
    return '';
  }
  # We'll need the numeric UID and GID for the user and group named "puppet".
  # The easiest and most reliable (in the sense of being able to trust the
  # returned value) way is to ask Augeas to read them from /etc/passwd and
  # /etc/group, if it works.  We won't be changing anything with Augeas here.
  try {
    $g->aug_init("/", 0);
  };
  unless($@ eq '') {
    carp "Unable to initialize libguestfs/libaugeas: $@";
    return '';
  }
  # On 2014-03-11, we had a strange phenomenon: libguestfs's Augeas couldn't
  # see /files/etc/group on oasis.grid, even though the file was there and
  # augtool on oasis.grid itself could see the file just fine. It could see
  # /files/etc/group on other guests on the same host, and when I copied
  # /etc/group and /etc/gshadow onto a temporary guest, it could see the file.
  # I still don't know what caused it, but we need to test for the situation
  # where libguestfs's Augeas thinks the file isn't there. Now, aug_get gets a
  # croak when the path isn't found, which causes the whole script to die, but
  # aug_match just returns an empty array, so test with aug_match first. I'm
  # doing this for both UIDs in /etc/passwd and GIDs in /etc/group because if
  # the problem can happen in one, it can presumably happen in the other.
  my @matches = ();
  my $uid = undef;
  try {
    @matches = $g->aug_match('/files/etc/passwd');
  };
  unless($@ eq '') {
    carp "Unable to run aug_match on /files/etc/passwd: $@";
    return '';
  }
  if($#matches >= 0) {
    try {
      $uid = $g->aug_get('/files/etc/passwd/puppet/uid');
    };
    unless($@ eq '') {
      carp "Unable to run aug_get on /files/etc/passwd/puppet/uid: $@";
    }
  } else {
    carp "/etc/passwd not available via Augeas -- downloading and parsing";
    $uid = &guestfs_get_id_from_file($g, '/etc/passwd', 'puppet', $dir);
  }
  my $gid = undef;
  try {
    @matches = $g->aug_match('/files/etc/group');
  };
  unless($@ eq '') {
    carp "Unable to run aug_match on /files/etc/group: $@";
    return '';
  }
  if($#matches >= 0) {
    try {
      $gid = $g->aug_get('/files/etc/group/puppet/gid');
    };
    unless($@ eq '') {
      carp "Unable to run aug_get on /files/etc/group/puppet/gid: $@";
    }
  } else {
    carp "/etc/group not available via Augeas -- downloading and parsing";
    $gid = &guestfs_get_id_from_file($g, '/etc/group', 'puppet', $dir);
  }
  $g->aug_close();
  # If we somehow couldn't get the UID or GID by any other means, assign them a
  # default -- 52 seems to be the default value used by the Puppet RPM for both
  # its UID and GID, at least most of the time.
  unless(defined($uid)) {
    carp "Unable to obtain a UID for puppet -- using the default of 52";
    $uid = 52;
  }
  unless(defined($gid)) {
    carp "Unable to obtain a GID for puppet -- using the default of 52";
    $gid = 52;
  }
  try {
    $g->chown($uid, $gid, "/etc/puppet/ssl/private_keys/$h.pem");
  };
  unless($@ eq '') {
    carp "Unable to chown /etc/puppet/ssl/private_keys/$h.pem: $@";
  }
  try {
    $g->chmod(0600, "/etc/puppet/ssl/private_keys/$h.pem");
  };
  unless($@ eq '') {
    carp "Unable to chmod /etc/puppet/ssl/private_keys/$h.pem: $@";
  }
  try {
    $g->chown($uid, $gid, "/etc/puppet/ssl/certs/$h.pem");
  };
  unless($@ eq '') {
    carp "Unable to chown /etc/puppet/ssl/certs/$h.pem: $@\n";
  }
  try {
    $g->chmod(0644, "/etc/puppet/ssl/certs/$h.pem");
  };
  unless($@ eq '') {
    carp "Unable to chmod /etc/puppet/ssl/certs/$h.pem: $@";
  }
  return 1;
}

sub guestfs_setup_sudoers(\%\%$) {
  # The question is who has sudo rights ab initio. Puppet creates a file called
  # /etc/sudoers.d/goc that looks like this:

  # Defaults:%goc   !requiretty
  # Defaults:%sudo-<accesshost>   !requiretty
  #
  # User_Alias      ADMINS = thomlee
  #
  # %sudoers        ALL=(ALL)       ALL
  # %sudo-<accesshost>         ALL=(ALL)       ALL
  # ADMINS          ALL=(ALL)       NOPASSWD: ALL

  # where <accesshost> is determined via a site-specific custom Facter fact
  # called by Puppet. Because Puppet runs during the stemcell build process,
  # this file is present on stemcell images, and <accesshost> is 'localhost' in
  # that case. When a stemcell image is used to build a VM and Puppet
  # subsequently runs on that VM, <accesshost> will be based on the hostname of
  # the new VM, but the problem is running Puppet and getting things set up
  # quickly. Puppet ordinarily runs via cron once every 30 minutes, but that's
  # not 'quickly.' A user in the 'sudoers' group or the 'sudo-localhost' group
  # (there is no 'sudo-localhost' group, by the way) would be able to run
  # Puppet immediately (or, more likely, have something like Ansible run it
  # immediately for them). That's not a problem. The problem arises when there
  # are offsite collaborators.

  # Offsite collaborators won't be in the 'sudoers' group, because that would
  # give them sudo privileges on every host, which is unacceptable from a
  # security perspective. We could create a 'sudo-localhost' group and put
  # offsite collaborators in it, but then they'd be able to sudo to any
  # just-created VM, even the ones that they shouldn't have access to. What's
  # more, offsite collaborators are already going to be in groups called
  # 'sudo-<accesshost>' geared toward what they're supposed to have access
  # to. We need to change that line to the appropriate group, and that's what
  # this subroutine does.

  # What we have to do is figure out what the <accesshost> string is based on
  # the hostname (using code derived from the Ruby code that does the same
  # thing in the site-specific custom Facter fact that Puppet uses), and create
  # a preliminary /etc/sudoers.d/goc file allowing the 'sudo-<accesshost>'
  # group to sudo immediately.

  # This subroutine requires a launched Sys::Guestfs object with a domain added
  # and drives mounted, a reference to a hash of the sort returned by
  # lookup_network_params, and a temporary directory.
  my($g, $net, $tmpdir) = @_;

  print "Configuring sudo ...\n";

  # The path to the file to create:
  my $sudofile = '/etc/sudoers.d/goc';

  # Decide what the accesshost string should be. Start with the short hostname.
  my($shorthost) = split /\./, $net->{public}->{hostname}, 2;
  my $accesshost = $shorthost;
  if($shorthost eq 'oasis-login-sl6') {
    $accesshost = $shorthost;
  } elsif($shorthost eq 'nukufetau') {
    $accesshost = 'backup';
  } elsif($shorthost eq 'freeman' or $shorthost eq 'huey' or $shorthost eq 'woodcrest') {
    $accesshost = 'devm';
  } elsif($shorthost =~ /^psvm\d+$/) {
    $accesshost = 'vm';
  } elsif($shorthost eq 'bundy' or $shorthost eq 'riley') {
    $accesshost = 'is';
  } elsif($shorthost eq 'puppet') {
    $accesshost = 'puppet';
  } elsif($shorthost eq 'dahmer') {
    $accesshost = 'rsv-old';
  } elsif($shorthost eq 'xd-login' or $shorthost eq 'vanheusen' or $shorthost eq 'osg-flock' or $shorthost eq 'leonard') {
    $accesshost = 'osg-xd';
  } elsif($shorthost =~ /^yum-internal/) {
    $accesshost = 'yum-internal';
  } else {
    $accesshost =~ s/-?\d+$//;
  }

  # Make the file.
  try {
    $g->write($sudofile, <<"EOF");
Defaults:%goc   !requiretty
Defaults:%sudo-$accesshost   !requiretty

User_Alias      ADMINS = thomlee

%sudoers        ALL=(ALL)       ALL
%sudo-$accesshost         ALL=(ALL)       ALL
ADMINS          ALL=(ALL)       NOPASSWD: ALL
EOF
    ;
  };
  unless($@ eq '') {
    carp "Failed to write $sudofile: $@";
    return '';
  }
  try {
    $g->chown(0, 0, $sudofile);
  };
  unless($@ eq '') {
    carp "Unable to chown $sudofile: $@";
    return '';
  }
  try {
    $g->chmod(0440, $sudofile);
  };
  unless($@ eq '') {
    carp "Unable to chmod $sudofile: $@";
    return '';
  }
  return 1;
}

sub guestfs_set_puppet_environment($) {
  # Given a launched Sys::Guestfs object with a domain added and drives
  # mounted, set the environment in /etc/puppet/puppet.conf to be
  # $CFG::PUPPET_ENV. If that is not set, leave it alone.
  my($g) = @_;

  # If $CFG::PUPPET_ENV is undefined, the user didn't specify an environment
  # with -e on the command line. Don't do anything.
  return 1 unless defined($CFG::PUPPET_ENV);

  # Augeas appears to have a lens for this; the file appears in augtool under
  # /files/etc/puppet/puppet.conf/main.

  try {
    $g->aug_init("/", 0);
  };
  unless($@ eq '') {
    carp "Unable to initialize libguestfs/libaugeas: $@";
    return '';
  }
  try {
    $g->aug_defvar('p', '/files/etc/puppet/puppet.conf/main');
  };
  aug_set_protect $g, '$p/environment', $CFG::PUPPET_ENV;
  try {
    $g->aug_save;
  };
  unless($@ eq '') {
    carp "aug_save failed: $@";
    return undef;
  }
  try {
    $g->aug_close;
  };
  unless($@ eq '') {
    carp "aug_close failed: $@";
    return undef;
  }
  return 1;
}

sub guestfs_setup_puppet_firstboot($) {
  # Given a launched Sys::Guestfs object with a domain added and drives
  # mounted, set the VM up to run Puppet on first boot. This means placing an
  # /opt/sbin/afterboot.sh script and setting up either /etc/rc.local (in the
  # pre-systemd case) or systemd to run it on boot.
  my($g) = @_;

  print "Setting Puppet up to run on first boot ...\n";
  # Place the afterboot.sh script.
  my $afterboot = '/opt/sbin/afterboot.sh';
  my $afterboot_contents = <<EOF;
#!/bin/bash

# Run on first boot, then remove what calls it so it doesn't run again
# Tom Lee <thomlee\@iu.edu>
# Begun 2016-11-18

# Fix path

PATH=/sbin:/bin:/usr/sbin:/usr/bin:/opt/sbin:/opt/bin:/usr/local/sbin:/usr/local/bin

# Stop if not root

if [[ \$EUID -ne 0 ]]; then
    echo "Must be root." > /dev/stderr
    exit 1
fi

# Find out whether we have rpm

if ! which rpm >&/dev/null; then
    echo "No rpm executable found; this script expects an RPM-based distro." > /dev/stderr
    exit 1
fi

# Find out whether we're SYSV or systemd

if rpm -q systemd >&/dev/null; then
    SYSTEMD=1
else
    SYSTEMD=
fi

# Now do what's necessary.

echo "\$(date):" >> /root/afterboot_facter.txt
echo -n "  goc_accesshost: " >> /root/afterboot_facter.txt
facter -p goc_accesshost >> /root/afterboot_facter.txt
echo -n "  anaconda: " >> /root/afterboot_facter.txt
facter -p anaconda >> /root/afterboot_facter.txt
puppet agent --no-daemonize --onetime >&/dev/null

# Now set things up so the system won't run this next time it boots.

if [[ \$SYSTEMD ]]; then
    # Set systemd's default target to 'multi-user'.
    systemctl set-default multi-user.target >&/dev/null
else
    # Remove the line that calls this script from /etc/rc.local. Complicating
    # this is the fact that /etc/rc.local is usually a symlink. We can use sed
    # to edit the line out with the -i option, but sed 4.2 (the version found
    # in RHEL 6 and 7) will remove the symlink and replace it with a regular
    # file unless we also use the --follow-symlinks option, which will edit the
    # file to which the symlink points instead. This was the default behavior
    # in sed 4.1 (the version of sed that RHEL 5 uses), though, and
    # --follow-symlinks didn't exist in that version.
    sedversion=\$(sed --version | head -n 1 | grep -Eo '[[:digit:]]+(\.[[:digit:]]+)*')
    IFS='.' read -ra sedversarr <<< "\$sedversion"
    symlinkoption=
    if [[ \${sedversarr[0]} -ge 4 ]] && [[ \${sedversarr[1]} -ge 2 ]]; then
        symlinkoption='--follow-symlinks'
    fi
    sed -i \$symlinkoption -r -e '/afterboot\.sh/d' /etc/rc.local >&/dev/null
fi
EOF
  ;
  try {
    $g->write($afterboot, $afterboot_contents);
  };
  unless($@ eq '') {
    carp "Unable to write $afterboot: $@";
    return '';
  }
  try {
    $g->chown(0, 0, $afterboot);
  };
  unless($@ eq '') {
    carp "Unable to chown $afterboot: $@";
    return '';
  }
  try {
    $g->chmod(0744, $afterboot);
  };
  unless($@ eq '') {
    carp "Unable to chmod $afterboot: $@";
    return '';
  }

  # Now set the system to run $afterboot on boot. Are we dealing with RHEL/CentOS 7 or greater?
  if($CFG::DISTRO eq '5' or $CFG::DISTRO eq '6' or $CFG::DISTRO eq 'c6') {
    # We are pre-systemd. Add a command to /etc/rc.local to run $afterboot and
    # make sure /etc/rc.local is executable. It should run at the end of the
    # boot process.
    try {
      $g->write_append('/etc/rc.local', <<"EOF");
$afterboot
EOF
      ;
    };
    unless($@ eq '') {
      carp "Unable to write /etc/rc.local: $@";
      return '';
    }
    try {
      $g->chmod(0744, '/etc/rc.local');
    };
    unless($@ eq '') {
      carp "Unable to chmod /etc/rc.local: $@";
      return '';
    }
  } else {
    # We're dealing with systemd. We'll have to make an
    # /etc/systemd/system/afterboot.service that runs $afterboot and enable it,
    # make an /etc/systemd/system/afterboot.target that wants afterboot.service
    # and runs after multi-user.target, and make afterboot.target the default
    # target. Then $afterboot will run at the end of the boot process. I know
    # this works because of extensive research in the systemd documentation,
    # and because of experimentation on VMs.

    # First write the service unit file.
    my $absvc = '/etc/systemd/system/afterboot.service';
    try {
      $g->write($absvc, <<EOF);
[Unit]
Description=Command to run after boot

[Service]
Type=oneshot
RemainAfterExit=True
ExecStart=/opt/sbin/afterboot.sh

[Install]
WantedBy=afterboot.target
EOF
      ;
    };
    unless($@ eq '') {
      carp "Unable to write $absvc: $@";
      return '';
    }

    # Now write the target unit file.
    my $abtgt = '/etc/systemd/system/afterboot.target';
    try {
      $g->write($abtgt, <<EOF);
[Unit]
Description=Custom target for jobs to run after boot
Requires=multi-user.target
After=multi-user.target
AllowIsolate=yes
EOF
      ;
    };

    # Enable the service.
    unless($g->is_dir('/etc/systemd/system/afterboot.target.wants')) {
      try {
	$g->mkdir_mode('/etc/systemd/system/afterboot.target.wants', 0755);
      };
      unless($@ eq '') {
	carp "Unable to mkdir /etc/systemd/system/afterboot.target.wants: $@";
	return '';
      }
    }
    try {
      $g->ln_s($absvc, '/etc/systemd/system/afterboot.target.wants/afterboot.service');
    };
    unless($@ eq '') {
      carp "Unable to enable afterboot.service: $@";
      return '';
    }

    # Make afterboot.target the default target.
    try {
      $g->ln_sf($abtgt, '/etc/systemd/system/default.target');
    };
    unless($@ eq '') {
      carp "Unable to make afterboot.target the default target: $@";
      return '';
    }
  }
}

sub build_vm_pxe_anaconda($) {
  # Creates a VM, then boots it using PXE so Anaconda will build an OS on it.
  # The Cobbler server is meant to recognize the hardware address in the case of
  # rebuild_stemcell or in the case of certain specially defined VMs.

  my($vmname) = @_;
  my $ghwaddr = &construct_hw_address($vmname, 'public');
  my $lhwaddr = &construct_hw_address($vmname, 'private');
  if($CFG::KVM) {
    # Make the disks
    my $ram_mib = $CFG::MEM_SIZE->in('MiB');
    my $console = $CFG::X11?'':'--noautoconsole';
    &create_vdisk_img("$CFG::VM_DIR/$vmname-hda.qcow2", $CFG::BASE_VM_SIZE, 0) || return '';
    &create_vdisk_img("$CFG::VM_DIR/$vmname-hdb.qcow2", $CFG::USR_LOCAL_SIZE, 1) || return '';

    # Show the drives to libvirt.
    $CFG::VMM->get_storage_pool_by_name('default')->refresh();

    # Create the VM.
    # --pxe: boot from PXE the first time even though it has hard drives
    # --os-type, --os-variant: optimize hardware settings for type of OS
    # --check-cpu: warn if the number of virtual CPUs exceeds the number of physical CPUs
    # -k: set the type of keyboard for the VNC console
    # -n: set the name ("domain") of the VM
    # -r: set the amount of RAM in MiB
    # --disk: add and configure a drive
    # --network: add and configure a network adapter
    # --autostart: the VM should start when the host boots up
    # --noreboot: the VM shouldn't reboot when installation is complete (this doesn't work anyway)
    # --wait: how long (in minutes) to wait for installation to finish (negative=forever)

    my $cmd = <<"EOF"
virt-install --pxe
  --os-type=linux --os-variant=rhel5.4
  --check-cpu -k en-us -n $vmname -r $ram_mib --vcpus=$CFG::NUMVCPUS
  --disk path="$CFG::VM_DIR/$vmname-hda.qcow2",bus=virtio,format=qcow2,cache=none
  --disk path="$CFG::VM_DIR/$vmname-hdb.qcow2",bus=virtio,format=qcow2,cache=none
  --network bridge=br0,model=virtio,mac=$ghwaddr
  --network bridge=br1,model=virtio,mac=$lhwaddr
  --autostart --noreboot --wait=-1 $console
EOF
      ;
    &test_cmd($cmd);

    # By default the VM should automatically reboot after installation (in
    # theory, at least; in practice it usually doesn't work), but we don't want
    # this, because we want to archive the disk image, not start it up.  To
    # this end, the PXE boot's kickstart should be configured to shutdown after
    # installation.  The virt-install command's --noreboot option should also
    # prevent it from rebooting after installation, and giving it a negative
    # value for its --wait time should make it wait indefinitely for the VM to
    # shut down after installation before continuing with this script.
    # Therefore, when we reach this point, the OS has been installed on the VM
    # and it has been shut down gracefully.  At this point we can copy the VM
    # to the server.
  } else {
    my @vmxtext = map {
      chomp($_);
      if(/\w\s*=\s*"/) {
	my($key, $value) = (/^\s*(\S+)\s*=\s*\"?([^\"]*)\"?\s*$/);
	my %hash = (key => $key, value => $value);
	\%hash;
      } else {
	$_;
      }
    } split(/\n/, <<"EOF");
#!/usr/bin/vmware
config.version = "8"
virtualHW.version = "4"
logging = "FALSE"
autostop = "softpoweroff"
memsize = "1024"
displayName = "$vmname"
guestOS = "other26xlinux-64"
priority.grabbed = "normal"
priority.ungrabbed = "normal"
powerType.powerOff = "hard"
powerType.powerOn = "hard"
powerType.suspend = "hard"
powerType.reset = "hard"

Ethernet0.present = "TRUE"
Ethernet0.virtualDev = "e1000"
Ethernet0.connectionType = "custom"
Ethernet0.vnet = "/dev/vmnet0"
ethernet0.addressType = "static"
ethernet0.address = "$ghwaddr"

Ethernet1.present = "TRUE"
Ethernet1.connectionType = "custom"
Ethernet1.vnet = "/dev/vmnet2"
Ethernet1.virtualDev = "e1000"
ethernet1.addressType = "static"
ethernet1.address = "$lhwaddr"

uuid.location = "00 11 22 33 44 55 66 77-88 99 aa bb cc dd ee ff"
uuid.bios = "00 11 22 33 44 55 66 77-88 99 aa bb cc dd ee ff"
uuid.action = "create"

floppy0.startConnected = "FALSE"
floppy0.fileName = "/dev/fd0"
floppy0.present = "FALSE"

ide0:0.present = "TRUE"
ide0:0.fileName = "hda.vmdk"
ide0:0.redo = ""

ide0:1.present = "TRUE"
ide0:1.fileName = "hdb.vmdk"
ide0:1.redo = ""

ide1:0.present = "FALSE"
ide1:0.fileName = ""
ide1:0.deviceType = "cdrom-image"
ide1:0.autodetect = "TRUE"
ide1:0.startConnected = "FALSE"

ide1:1.present = "FALSE"
ide1:1.fileName = ""
ide1:1.redo = ""

tools.syncTime = "FALSE"

checkpoint.vmState = ""

sched.mem.pshare.enable = "FALSE"
mainMem.useNamedFile = "FALSE"
MemTrimRate = "0"
MemAllowAutoScaleDown = "FALSE"

machine.id = "replace-with-vm-hostname"
autostart = "none"
EOF
;

    # Write this to the .vmx file
    my $vmxfile = "$CFG::VM_DIR/$vmname/$vmname.vmx";
    unless($CFG::TEST_MODE) {
      my $fh = IO::File->new();
      $fh->open(">$vmxfile") || die "Unable to open $vmxfile: $!\n";
      foreach my $line (@vmxtext) {
	if(ref($line)) {
	  $fh->printf("%s = \"%s\"\n", $line->{key}, $line->{value});
	} else {
	  $fh->printf("%s\n", $line);
	}
      }
      $fh->close();
    }

    # Make the virtual disk images
    &create_vdisk_img("$CFG::VM_DIR/$vmname/hda.vmdk", $CFG::BASE_VM_SIZE, 0) || return '';
    &create_vdisk_img("$CFG::VM_DIR/$vmname/hdb.vmdk", $CFG::USR_LOCAL_SIZE, 1) || return '';

    # Get the nvram file if it exists
    if(-e "$CFG::ARCHIVE_DIR/nvram.vmw") {
      &test_cmd("install -oroot -gvm -m0660 $CFG::ARCHIVE_DIR/nvram.vmw $CFG::VM_DIR/$vmname/nvram");
    }

    # Make sure we have modes and permissions set correctly
    &set_owners_perms("$CFG::VM_DIR/$vmname");

    # Register the VM.
    &test_cmd("vmware-cmd -s register $vmxfile");

    # Boot the VM so it will run Anaconda via PXE.
    &do_start($vmname);

    # Wait for it to be down again.
    print(<<"EOF");
Waiting while stemcell installs the OS on itself.

Note that due to a bug in VMware Server that will certainly never be fixed
because VMware Server was end-of-lifed in mid-2011, there is likely to be a
long pause during the initial kernel boot decompression stage.  This pause can
be as long as 7 minutes.

This bug is not present in KVM virtual machines.
EOF
    ;
    unless($CFG::TEST_MODE) {
      while(&vm_running($vmname)) {
	sleep(5);
      }
    }
  }
  return 1;
}

sub get_term_width() {
  # Use an ioctl call to get the terminal width.  Not portable to non-Linux
  # systems.  Changing screen width (e.g. resizing a terminal window) while
  # running the script won't result in a different value from this.
  my $winsize = "\0"x8;
  my $TIOCGWINSZ = 0x40087468;
  my $cols;
  if(ioctl(STDOUT, $TIOCGWINSZ, $winsize)) {
    (undef, $cols) = unpack('S4', $winsize);
  } else {
    $cols = 80;
  }
  return($cols);
}

sub print_thermometer($$) {
  # Prints a status thermometer with the given label and fraction (0-1).  How
  # to use this:
  #
  # 1. Call &print_thermometer(<your label>, 0)
  # 2. As progress occurs, call &print_thermometer(<same label>, <fraction>)
  # 3. When done, call &print_thermometer(<same label>, 1)
  # 4. Print a newline
  #
  # It helps if you don't print anything else during this process, except
  # perhaps error messages, and if you do, print a newline first, or they'll
  # get printed oddly.

  my($label, $fraction) = @_;
  $fraction = ($fraction > 1.0)?1.0:$fraction;
  # This will cause the thermometer to extend to the full width of the
  # terminal, whatever it is -- although it will go to just printing
  # percentages if the terminal is too small.
  my($width) = &get_term_width();
  # Now calculate the room we have for the thermometer portion -- 9 is the
  # length of the fixed-length stuff (': [' and '] xxx%')
  my($room) = $width - 9 - length($label);
  if($room > 0) {
    printf("%s: [%s%s] %3d%%\r",
	   $label,
	   "="x($room*$fraction + 0.5),
	   " "x($room*(1.0 - $fraction) + 0.5),
	   $fraction*100);
  } else {
    # If the terminal is too narrow for some reason, just print the label and
    # percentage.  This would only happen if the terminal was narrower than
    # about the length of the label plus 10 characters, so that would require a
    # really narrow terminal or a really long label.
    printf("%s: %3d%%\r", $label, $fraction*100);
  }
}

sub make_tarball(%) {
  # Wrapper for tar file creation.  Arguments should be in the form of a hash.
  # Keys:
  # file (required): Path to tar file to create.
  # chdir (optional): Directory to change to before archiving files.
  # include (required): Path or ref to array of paths of files to include.
  # exclude (optional): Path or ref to array of paths of files to exclude.
  # Returns true on success, false on failure.

  my(%args) = @_;
  unless($args{file}) {
    carp "Unspecified tarball path.";
    return '';
  }

  # Get the size of all files -- this means adding up the size of all files
  # included and subtracting the size of all files excluded.
  my $save_cwd = cwd();
  # The includes and excludes are pathed relative either to the CWD or to
  # $args{chdir}, if given, so if we're going to look at those files, we'll
  # have to change to that directory if it's given.
  if($args{chdir}) {
    chdir $args{chdir};
  }
  # Make an array of the include or includes -- it could either be a single
  # path or a reference to an array of paths, so handle both those
  # possibilities.
  my @includes = ();
  if(ref($args{include})) {
    push(@includes, @{$args{include}});
  } else {
    push(@includes, $args{include});
  }
  # Now go through every path in @includes and add up the size of every file --
  # if it's a directory, recurse through it and add in the size of every file
  # found.  Probably the best way to do this is with the "du -s" command.
  my $totalsize = 0;
  foreach my $inc (@includes) {
    my($size) = split(/\s+/, `du -cs --block-size=1 $inc | tail -n 1`, 2);
    $size ||= 0;
    $totalsize += $size;
  }
  # Now do the same for excludes.
  my @excludes = ();
  if($args{exclude}) {
    if(ref($args{exclude})) {
      push(@excludes, @{$args{exclude}});
    } else {
      push(@excludes, $args{exclude});
    }
  }
  foreach my $exc (@excludes) {
    next unless(-e <$exc>);
    my($size) = split(/\s+/, `du -cs --block-size=1 $exc | tail -n 1`, 2);
    $totalsize -= $size;
  }
  debug_printf "\$totalsize = $totalsize bytes";
  $totalsize /= 1048576;
  debug_printf "\$totalsize = $totalsize MiB";
  # Now $totalsize should, theoretically, be the total size in MiB of the files
  # that are about to be tarballed.  When we use the "--checkpoint" option to
  # tar, with "-b 2048" specified, we will get checkpoint messages after
  # processing about every 10 MiB of input data (to be precise, the messages
  # are printed every 10 records, and a record is 512 blocks, and we specified
  # a 2048-byte block size).  They look like this:
  #
  # tar: Write checkpoint 10
  # tar: Write checkpoint 20
  #
  # etc.  We should thus be able to estimate the completion percentage.
  my $tar_cmd = 'tar zcSf '.$args{file}.' --checkpoint -b 2048';
  if($args{chdir}) {
    $tar_cmd .= ' -C '.$args{chdir};
  }
  foreach my $exc (@excludes) {
    $tar_cmd .= " --exclude $exc";
  }
  foreach my $inc (@includes) {
    $tar_cmd .= " $inc";
  }
  my $result = 1;
  if($CFG::TEST_MODE) {
    test_printf '%s', $tar_cmd;
    $result = 1;
  } else {
    &print_thermometer('tar', 0);
    my $fh = IO::File->new();
    # Wackiness from the IPC::Open3 and Symbol modules.  The gensym function
    # comes from the Symbol module and generates a reference to an anonymous
    # glob.  The open3 function runs a command in a shell and connects its
    # stdin, stdout, and stderr (in that order) to accessible filehandles.  In
    # this case we're not sending it any input so we hand it an anonymous
    # gensym for that, we want its output to go directly to this script's
    # STDERR handle, and we want the command's stderr for monitoring purposes.
    if(defined(my $pid = open3(gensym, ">&STDERR", $fh, $tar_cmd))) {
      $| = 1;
      while(defined(my $line = <$fh>)) {
	chomp($line);
	if($line =~ /^tar: write checkpoint \d+$/i) {
	  my($records) = ($line =~ /^tar: write checkpoint (\d+)$/i);
	  debug_printf "\$records = $records";
	  &print_thermometer('tar', $records/$totalsize);
	}
      }
      &print_thermometer('tar', 1);
      print("\n");
    } else {
      carp "Error: Unable to create tarball: $!";
      $result = '';
    }
    $fh->close();
  }
  chdir $save_cwd;
  return $result;
}

sub tarball_stemcell() {
  # Tarball a built stemcell (see &rebuild_stemcell and &build_vm_pxe_anaconda)
  # to the stemcell archive location.  Returns true if everything went OK,
  # false otherwise.

  my $result;
  my $destpath;

  # Examine $CFG::STEMCELL_TARBALL to see if it's been set (via the -f option)
  # -- if it's a relative filename, put it in $CFG::ARCHIVE_DIR; if it's an
  # absolute path, put it there, and if it's a directory, make up a reasonable
  # name and put it there.
  if($CFG::STEMCELL_TARBALL) {
    debug_printf "\$CFG::STEMCELL_TARBALL = '%s'", $CFG::STEMCELL_TARBALL;
    if(-d $CFG::STEMCELL_TARBALL) { # If it's a directory, standard filename there
      $destpath = sprintf('%s/%s', $CFG::STEMCELL_TARBALL, &stemcell_filename());
    } elsif($CFG::STEMCELL_TARBALL =~ /^\//) { # Absolute path -- use it
      $destpath = $CFG::STEMCELL_TARBALL;
    } else { # Some other filename -- usual directory, that filename
      $destpath = sprintf('%s/%s', $CFG::ARCHIVE_DIR, $CFG::STEMCELL_TARBALL);
    }
  } else { # $CFG::STEMCELL_TARBALL is unset
    debug_printf "\$CFG::STEMCELL_TARBALL = '(undef)'";
    $destpath=sprintf('%s/%s', $CFG::ARCHIVE_DIR, &stemcell_filename());
  }
  debug_printf "\$destpath = '$destpath'";

  print("Exporting VM ...\n");
  &preserve_old_tarball($destpath);
  if($CFG::KVM) {
    if($CFG::TEST_MODE) {
      test_printf 'Writing stemcell to %s', $destpath;
    } else {
      # Dump the VM's XML definitions to a temporary file
      my $fh = IO::File->new(">/tmp/$CFG::STEMCELL.xml");
      die "ERROR: Unable to open /tmp/$CFG::STEMCELL.xml for writing: $!\n" unless defined($fh);
      $fh->print($CFG::VMM->get_domain_by_name($CFG::STEMCELL)->get_xml_description());
      $fh->close;
      # Archive the main disk image and the temporary XML definition file.
      $result = &make_tarball
	(
	 file => $destpath,
	 chdir => "/",
	 include => [
		     "/tmp/$CFG::STEMCELL.xml",
		     "$CFG::VM_DIR/$CFG::STEMCELL-hda.qcow2",
		    ],
	);
      # Remove the temporary XML file
      &test_cmd("rm -f /tmp/$CFG::STEMCELL.xml");
    }
  } else { # The VMware case
    # Archive the main disk image, the .vmx definition file, and really just
    # about everything we find in the VM's directory
    $result = &make_tarball(
		       file => $destpath,
		       chdir => "/$CFG::VM_DIR",
		       include => "$CFG::STEMCELL",
		       exclude => [
				   "$CFG::STEMCELL/hdb.vmdk",
				   "$CFG::STEMCELL/*.pl",
				   "$CFG::STEMCELL/*.bak",
				   "$CFG::STEMCELL/*.log",
				   "$CFG::STEMCELL/lost+found",
				  ],
		      );
#    $result = &test_cmd(<<"EOF");
#tar zcSvf $destpath
#  -b 2048
#  -C /$CFG::VM_DIR
#  --exclude $CFG::STEMCELL/hdb.vmdk
#  --exclude $CFG::STEMCELL/*.pl
#  --exclude $CFG::STEMCELL/*.bak
#  --exclude $CFG::STEMCELL/*.log
#  --exclude $CFG::STEMCELL/lost+found
#  $CFG::STEMCELL
#EOF
#    ;
  }
  return $result;
}

sub install_stemcell($) {
  # Copies the stemcell from the server and puts things in the right places.
  # Returns true if successful, false if not.

  my($vmname) = @_;
  my $result;
  my $srcpath = &stemcell_srcpath();

  unless(-e $srcpath) {
    carp "File $srcpath not found.";
    return '';
  }
  print("Unpacking stemcell tarball ...\n");
  if($CFG::KVM) {
    $result = &test_cmd("tar zxf $srcpath -C /");
  } else {
    $result = &test_cmd("tar zxf $srcpath -C $CFG::VM_DIR/$vmname --strip-components=1");
  }
  return ($result == 0)?1:'';
}

sub customize_vm($) {
  # After installing a stemcell (see install_stemcell), customize it to the
  # specifications given in the config file and on the command line.  Returns
  # true if successful, false if there was some kind of problem.

  my($vmname) = @_;
  my $result;

  # Get or construct all the network parameters.  We'll need them soon.
  my $net = &lookup_network_params($vmname);

  if($CFG::KVM) {
    # Rename the virtual disk files, then modify the XML file in
    # /tmp/$CFG::STEMCELL.xml and import it as whatever it is to be named.

    unless((-e "$CFG::VM_DIR/$CFG::STEMCELL-hda.qcow2") || $CFG::TEST_MODE) {
      die "Something is very wrong: After unpacking $CFG::STEMCELL image,\ndisk image $CFG::VM_DIR/$CFG::STEMCELL-hda.qcow2 does not exist.\nUnable to proceed.\n";
    }
    # Use XML::Twig to modify the XML
    my $t = XML::Twig->new();
    if($CFG::TEST_MODE) {
      # This is taken from a typical KVM XML dump; we're using it so test mode
      # has something to do
      $t->parse(<<"EOF");
<domain type='kvm'>
  <name>$CFG::STEMCELL</name>
  <uuid>951cc26a-bda1-9ffc-3f3c-dff3f37a4524</uuid>
  <memory>1048576</memory>
  <currentMemory>1048576</currentMemory>
  <vcpu>1</vcpu>
  <os>
    <type arch='x86_64' machine='rhel6.2.0'>hvm</type>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
    <pae/>
  </features>
  <clock offset='utc'/>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>restart</on_crash>
  <devices>
    <emulator>/usr/libexec/qemu-kvm</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' cache='none'/>
      <source file='/var/lib/libvirt/images/$CFG::STEMCELL-hda.qcow2'/>
      <target dev='hda' bus='virtio'/>
      <alias name='virtio-disk0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x06' function='0x0'/>
    </disk>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' cache='none'/>
      <source file='/var/lib/libvirt/images/$CFG::STEMCELL-hdb.qcow2'/>
      <target dev='hdb' bus='virtio'/>
      <alias name='virtio-disk1'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x07' function='0x0'/>
    </disk>
    <controller type='ide' index='0'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x1'/>
    </controller>
    <interface type='bridge'>
      <mac address='52:54:00:04:00:00'/>
      <source bridge='br0'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
    </interface>
    <interface type='bridge'>
      <mac address='52:54:00:06:00:00'/>
      <source bridge='br1'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0'/>
    </interface>
    <serial type='pty'>
      <target port='0'/>
    </serial>
    <console type='pty'>
      <target type='serial' port='0'/>
    </console>
    <input type='mouse' bus='ps2'/>
    <graphics type='vnc' port='-1' autoport='yes' keymap='en-us'/>
    <video>
      <model type='cirrus' vram='9216' heads='1'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x0'/>
    </video>
    <memballoon model='virtio'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x05' function='0x0'/>
    </memballoon>
  </devices>
</domain>
EOF
      ;
    } else {
      $t->parsefile("/tmp/$CFG::STEMCELL.xml");
    }
    return '' unless $t;
    # Modify the XML:
    # VM name
    my($name) = $t->get_xpath('./name[1]');
    $name->set_text($vmname);

    # UUID -- libvirt won't let any two VMs have the same UUID on the same
    # host.  This is why I'm using "$vmname.goc" as my domain name -- if
    # we used "$short.goc", one couldn't have "foo.1" and "foo.2" on the same
    # host.
    my($uuid) = $t->get_xpath('./uuid[1]');
    $uuid->set_text(&generate_uuid($vmname));

    # System RAM
    my($memory) = $t->get_xpath('./memory[1]');
    $memory->set_text($CFG::MEM_SIZE->in('KiB'));
    # Not sure what this is, but it should be the same as $memory
    my($currentMemory) = $t->get_xpath('./currentMemory[1]');
    $currentMemory->set_text($memory->text());

    # Number of CPUs
    my($vcpu) = $t->get_xpath('./vcpu[1]');
    $vcpu->set_text($CFG::NUMVCPUS);

    # Network interfaces
    my @interfaces = $t->get_xpath('./devices/interface[@type="bridge"]');
    foreach my $elt (@interfaces) {
      my $if = $elt->first_child('source')->{att}->{bridge};
      $elt->first_child('mac')->{att}->{address} = $net->{($if eq 'br1')?'private':'public'}->{hwaddr};
    }

    # Disk files
    my @disks = $t->get_xpath('./devices/disk[@type="file"]');
    foreach my $elt (@disks) {
      $elt->first_child('source')->{att}->{file} =~ s/$CFG::STEMCELL/$vmname/;
    }
    # Will also have to recreate $CFG::STEMCELL-hdb.qcow2 and rename both disk image
    # files
    &create_vdisk_img(sprintf("%s/%s-hdb.qcow2", $CFG::VM_DIR, $vmname),
		      $CFG::USR_LOCAL_SIZE, 1) || return '';
    $result = &test_cmd(sprintf('mv %s/%s-hda.qcow2 %s/%s-hda.qcow2',
				$CFG::VM_DIR, $CFG::STEMCELL, $CFG::VM_DIR, $vmname));
    return '' unless($result == 0);
    if($CFG::TEST_MODE) {
      test_printf 'refresh default storage pool';
      test_printf "define new domain '%s'", $vmname;
      test_printf "set autostart parameter of domain '%s'", $vmname;
    } else {
      debug_printf 'XML contents: %s', $t->sprint();
      $CFG::VMM->get_storage_pool_by_name('default')->refresh();
      my $dom = $CFG::VMM->define_domain($t->sprint());
      return '' unless($dom);
      $dom->set_autostart(($CFG::NOAUTOSTART)?0:1);
    }

    # Then we'll have to add a .pl file to /opt/etc/gocvm on hda with the
    # config info using libguestfs
    my $tplfh = &make_temp_gocvm_file
      (
       net => $net,
       autoinstall => $CFG::AUTOINSTALL,
       noautonet => $CFG::NOAUTONET,
       called_as => $CFG::CALLED_AS,
       distro => $CFG::DISTRO,
      );
    return '' unless $tplfh;
    my $tmpconf = $tplfh->filename;
    if($CFG::TEST_MODE) {
      test_printf 'putting /opt/etc/gocvm/mkvm.pl in place on disk image';
    } else {
      my $g = Sys::Guestfs->new();
      $g->add_domain($vmname);
      print "Making prelaunch changes to filesystem ...\n";
      $g->launch();
      &guestfs_mount_all($g);
      $g->mkdir_p('/opt/etc/gocvm');
      $g->upload($tmpconf, '/opt/etc/gocvm/mkvm.pl');
      unless($CFG::NOAUTONET) {
	&guestfs_set_net_parameters($g, $net);
	my $tempdir = File::Temp::tempdir('customizevm.XXXXXXXX', DIR=>'/tmp', CLEANUP => 1);
	&guestfs_sign_ssh_key($g, $net, $tempdir);
	&guestfs_create_sign_puppet_cert($g, $net, $tempdir);
	&guestfs_setup_sudoers($g, $net, $tempdir);
      }
      if($CFG::PUPPET_ENV) {
	&guestfs_set_puppet_environment($g);
      }
      if($CFG::PUPPET_FIRSTBOOT) {
	&guestfs_setup_puppet_firstboot($g);
      }
      $g->umount_all();
      $g->shutdown();
      $g->close();
    }
    system("cat $tmpconf") if($CFG::DEBUG_MODE);
    $tplfh->close();
    $result = &test_cmd("rm -f /tmp/$CFG::STEMCELL.xml");
    return '' unless($result == 0);
  } else { # The VMware case
    # Rename .vmx file
    $result = &test_cmd("rename $CFG::STEMCELL. $vmname. $CFG::VM_DIR/$vmname/$CFG::STEMCELL.*");
    return '' unless($result == 0);
    my $vmxfile = "$CFG::VM_DIR/$vmname/$vmname.vmx";

    # Autostart parameter
    my $autostart = $CFG::NOAUTOSTART?'none':'poweron';

    # Get VM host's hostname
    my $thishost = hostname;
    unless(defined $thishost and $thishost ne '') {
      carp "Unable to determine hostname of VM host";
    }
    chomp $thishost if $thishost;
    my @hostparts = split(/\./, $thishost, 2);
    my $shorthost = $hostparts[0];

    # Distro and version/subversion/minor version numbers
    my $distro = '';
    my $distv = '';
    my $distsubv = '';
    my $distminv = '';
    # If $CFG::DISTRO is a number, it's a RHEL major version.
    if($CFG::DISTRO =~ /^\d+$/) {
      $distro = 'RHEL';
      $distv = $CFG::DISTRO;
    } elsif($CFG::DISTRO =~ /^c\d+$/i) {
      # If $CFG::DISTRO begins with 'c' and is followed by at least one digit,
      # it's CentOS, and the number is the major version.
      $distro = 'CentOS';
      ($distv) = ($CFG::DISTRO =~ /^c(\d+)$/i);
    }

    # Make the necessary changes to the .vmx file
    my %vmxchanges =
      (
       displayName => $vmname,
       autostart => $autostart,
       memsize => $CFG::MEM_SIZE->in('MiB'),
       'machine.id' => $shorthost,
       numvcpus => $CFG::NUMVCPUS,
       'uuid.action' => 'create',
       'ethernet0.address' => $net->{public}->{hwaddr},
       'ethernet1.address' => $net->{private}->{hwaddr},
       'guestinfo.vmhost' => $shorthost,
       'guestinfo.autoinstall' => $CFG::AUTOINSTALL?'1':'',
       'guestinfo.service' => $net->{service},
       'guestinfo.instance' => $net->{instance},
       'guestinfo.noautonet' => $CFG::NOAUTONET?'1':'',
       'guestinfo.rebuilding' => ($CFG::CALLED_AS eq 'rebuild_stemcell')?'1':'',
       'guestinfo.distro' => $distro,
       'guestinfo.distv' => $distv,
       'guestinfo.distsubv' => $distsubv,
       'guestifno.distminv' => $distminv,
       'guestinfo.randomhwaddrs' => ($net->{public}->{ipv4} or $net->{public}->{ipv6})?'':'1',
       'guestinfo.suggest_ip_eth0' => $net->{public}->{ipv4}->addr,
       'guestinfo.suggest_ip_eth1' => $net->{private}->{ipv4}->addr,
       'guestinfo.suggest_mask_eth0' => $net->{public}->{ipv4}->mask,
       'guestinfo.suggest_mask_eth1' => $net->{private}->{ipv4}->mask,
       'guestinfo.suggest_ipv6_eth0' => ip_canonical($net->{public}->{ipv6}, 1),
       'guestinfo.suggest_ipv6_eth1' => ip_canonical($net->{private}->{ipv6}, 1),
       'guestinfo.suggest_gateway' => $main::VLANDATA{public}->{gateway}->{ipv4},
       'guestinfo.suggest_gateway_ipv6' => $main::VLANDATA{public}->{gateway}->{ipv6}.'%'.$main::VLANDATA{public}->{intf},
       'guestinfo.suggest_hostname_eth0' => $net->{public}->{hostname},
       'guestinfo.suggest_hostname_eth1' => $net->{private}->{hostname},
      );
    &modify_vmxfile($vmxfile, \%vmxchanges) || return '';

    # Create the /dev/hdb disk.
    &create_vdisk_img(sprintf("%s/%s/hdb.vmdk", $CFG::VM_DIR, $vmname),
		      $CFG::USR_LOCAL_SIZE, 1) || return '';

    # Tell VMware about the new VM
    &register_vm($vmname) || return '';

    # Set the owner/group/permissions of the new files
    &set_owners_perms("$CFG::VM_DIR/$vmname") || return '';
  }
  return 1;
}

sub fix_vmware_perl_api_errors {
  # Kill off the "Use of uninitialized value" errors
  my $vmperl_start = "/usr/lib64/perl5";
  my $vmperl_name = "VmPerl.pm";
  &test_cmd("find $vmperl_start -name $vmperl_name -print0 | xargs -0 sed -i.bak -re \"s/return Version\\(\\);/return Version() || '';/\"");
}

# Now we finally have the subroutines that handle the commands, with the help
# of all the above subroutines.

sub preserve_old_tarball($) {
  # Retain a few old stemcell tarballs.  Old tarballs will use Emacs-style
  # backup notation -- they will have a ".~1~", ".~2~", etc. inserted after the
  # file extension at the end of the filename
  # (e.g. stemcell-x86_64-5-kvm.tgz.~1~).  The configuration setting $CFG::NBAK
  # determines how many backup files to keep (if $CFG::NBAK is 3, then we will
  # have file, file.~1~, file.~2~, and file.~3~ by the time we're done).

  my($path) = @_;
  my $scfile = &stemcell_filename();

  # No point in doing anything if $path doesn't exist already.
  return unless(-e $path);
  # There's already a $path.  Move it aside safely.
  my %dir;
  tie %dir, 'IO::Dir', $CFG::ARCHIVE_DIR, DIR_UNLINK;
  # Of course if there are already backup tarballs, move them aside too.
  # Collect the numbers of any files that fit the pattern.  Not assuming that
  # they're sequential.
  my @existing = sort {
    $a <=> $b
  } map {
    /\.~(\d+)~$/
  } grep {
    /^\Q$scfile\E\.~\d+~$/
  } keys(%dir);
  # We want to retain only the most recent ($CFG::NBAK - 1, since we'll be
  # adding another) of them.  Delete any older than that.
  if($#existing >= ($CFG::NBAK - 1)) {	# We'll be deleting some
    my @toohigh = @existing[($CFG::NBAK - 1)..$#existing];
    foreach my $i (@toohigh) {
      if($CFG::TEST_MODE) {
	test_printf 'delete %s.~%d~', $scfile, $i;
      } else {
	delete $dir{sprintf('%s.~%d~', $scfile, $i)};
      }
    }
    $#existing = $CFG::NBAK - 2;
  }
  # We're about to make changes, so let's not confuse IO::Dir by leaving a tied
  # variable around.  Not that we'll probably use IO::Dir for the rest of this
  # routine, but just in case.
  untie %dir;
  # To prevent clobbering, rename them to a temporary scheme.
  my $j = 2;
  my @new = ();
  foreach my $i (@existing) {
    push(@new, $j);
    if($CFG::TEST_MODE) {
      test_printf 'rename %s.~%d~ -> %s.tmp.~%d~', $path, $i, $path, $j;
    } else {
      rename(sprintf("%s.~%d~", $path, $i),
	     sprintf("%s.tmp.~%d~", $path, $j));
    }
    ++$j;
  }
  # Now rename them to a sequence of 2, ..., $CFG::NBAK
  $j = 2;
  foreach my $i (@new) {
    if($CFG::TEST_MODE) {
      test_printf 'rename %s.tmp.~%d~ -> %s.~%d~', $path, $i, $path, $j;
    } else {
      rename(sprintf("%s.tmp.~%d~", $path, $i),
	     sprintf("%s.~%d~", $path, $j));
    }
    ++$j;
  }
  # Finally, rename the one without a backup extension to .~1~.
  if($CFG::TEST_MODE) {
    test_printf 'rename %s -> %s.~1~', $path, $path;
  } else {
    rename($path, "$path.~1~");
  }
}

sub detect_vmware_snapshots($) {
  # Return true if there are any snapshots in $vmname, false if not.
  # Now, one could just look for files like foo-Snapshot1.vmsn, but it's really
  # better to follow the data pointers in the files.

  # How VMware does snapshots (determined empirically): When the snapshot is
  # created, VMware "freezes" the current state of the virtual disk files and
  # creates delta files with pointers back to the frozen base disk files.  For
  # example, before the snapshot, virtual machine "foo", in file "foo.vmx",
  # might have:

  # ide0:0.present = "TRUE"
  # ide0:0.filename = "foo-hda.vmdk"

  # and foo-hda.vmdk will have, among other things, settings like this:

  # CID=aa142402
  # parentCID=ffffffff

  # After the snapshot, the .vmx file will change:

  # ide0:0.filename = "foo-hda-000001.vmdk"

  # and a new virtual disk file will appear, called foo-hda-000001.vmdk, with a
  # setting like this:

  # CID=7a9b51be
  # parentCID=aa142402
  # parentFileNameHint="foo-hda.vmdk"

  # Also, the file foo.vmsd will be modified; this file always contains
  # information about the current active snapshots (and sometimes some inactive
  # ones).  You will see something like this:

  # snapshot.numSnapshots = "1"
  # snapshot.current = "1"
  # snapshot0.uid = "1"
  # snapshot0.filename = "foo-Snapshot1.vmsn"
  # snapshot0.numDisks = "1"
  # snapshot0.disk0.fileName = "foo-hda.vmdk"
  # snapshot0.disk0.node = "ide0:0"

  # As you see, to find the current snapshot, we must look up its snapshot UID
  # in snapshot.current, then find N such that snapshotN.uid is equal to
  # snapshot.current.  It is "snapshot0" in this case.  The foo-Snapshot1.vmsn
  # file contains various saved data plus a saved copy of the original .vmx
  # file.  It's in a binary format that isn't easily parsable by a script like
  # this one.

  # Complicating things is the fact that multiple snapshots can happen.  If the
  # current snapshot is a child of another snapshot, there will be a line like

  # snapshot0.parent = "5"

  # in the .vmsd file, and you'll have to track down the one with UID "5".  You
  # can track the snapshots back that way.  Each snapshot record will have a
  # "fileName" element for each disk, and that element reflects the true
  # "snapshot" -- not the disk file currently being modified (because that one
  # is the one listed in the .vmx file) but the one that was "frozen" when this
  # snapshot was created.

  # At any rate, we just want to know if there are any snapshots.  What that
  # means is that we open the .vmsd file and see what snapshot.numSnapshots
  # says.  If it says "0", or if there is no .vmsd file, there are no
  # snapshots.  If the file exists and the value is nonzero, there are.

  my($vmname) = @_;
  my $vmsd = "$CFG::VM_DIR/$vmname/$vmname.vmsd";
  # If there's no .vmsd file, there are no snapshots.
  return '' unless(-e $vmsd);
  my $fh = IO::File->new();
  # If the file can't be opened, something's wrong -- for one thing, we should
  # be root.
  unless($fh->open("<$vmsd")) {
    carp "Unable to open $vmsd: $!";
    return '';
  }
  my $line;
  my $num = 0;
  while(defined($line = <$fh>)) {
    # Look for the snapshot.numSnapshots line
    if($line =~ /^\s*snapshot\.numsnapshots/i) {
      # Save the number and stop reading; this is all we need
      ($num) = ($line =~ /^\s*snapshot\.numsnapshots\s*=\s*"?(\d+)"?/i);
      last;
    }
  }
  $fh->close();
  if($num > 0) {
    return 1;
  } else {
    return '';
  }
}

sub merge_kvm_snapshots($) {
  # KVM calls merging snapshots "deleting" them, which sounds drastic, but
  # actually no data is lost.  Reverting to a snapshot instantly loses data,
  # but "revert" sounds like you're somehow preserving something.  Anyway, this
  # deletes all of the given KVM guest domain's snapshots.
  my($vmname) = @_;
  my $dom = $CFG::VMM->get_domain_by_name($vmname);
  # Now, I don't know whether the internal structures will change as I delete
  # snapshots, so I'll get a list of their names, which I know won't change,
  # and delete them by name.
  my @sss = $dom->list_all_snapshots();
  foreach my $ss (@sss) {
    my $ssname = $ss->get_name();
    printf("Deleting snapshot %s ...\n", $ssname);
    unless($CFG::TEST_MODE) {
      $dom->get_snapshot_by_name($ssname)->delete();
    }
  }
}

sub merge_vmware_snapshots($) {
  # Merge the snapshots on the current VM, if there are any.  See
  # &detect_vmware_snapshots() for more information about how VMware stores
  # snapshot information.  All we should have to do here is test for their
  # existence using that subroutine, then run the "vmrun deleteSnapshot"
  # command until there aren't any more of them.

  my($vmname) = @_;
  printf("Merging snapshots.\n");
  if($CFG::TEST_MODE) {
    &test_cmd("vmrun deleteSnapshot $CFG::VM_DIR/$vmname/$vmname.vmx");
  } else {
    do {
      system("vmrun deleteSnapshot $CFG::VM_DIR/$vmname/$vmname.vmx");
    } while(&detect_vmware_snapshots($vmname));
  }
}

sub convert_vmware_disks($) {
  # Primarily this is for exportvm/importvm, because qemu-img can't convert a
  # VMware virtual disk image unless it's in monolithic format.  Determine
  # whether there are any split disks, and if there are, convert them to
  # monolithic via the "vmware-vdiskmanager -r -t 0" command.  (Be sure to
  # change the file permissions.)

  # Are there any split disks?  First look in the .vmx file to see what disks
  # there are, then in each one search for a createType element.  If it's
  # "monolithicSparse", that's what we want, and no conversion is necessary.

  # If there are any disks whose files don't end in .vmdk, treat them as not
  # present.  I can't support every possible weird variation, like .iso files,
  # disk partitions, logical volumes, etc.

  # This returns a reference to a list of the paths of converted disk files
  # that were created, if successful.  If unsuccessful, returns '' (Perl's
  # default false value).

  my($vmname) = @_;
  my %driveofnode =
    (
     'ide0:0' => 'hda',
     'ide0:1' => 'hdb',
     'ide1:0' => 'hdc',
     'ide1:1' => 'hdd',
    );
  my %diskdata = ();
  my $fh = IO::File->new();
  my $vmdir = "$CFG::VM_DIR/$vmname";
  my $vmxfile = "$vmdir/$vmname.vmx";
  my @created_files = ();
  unless($fh->open("<$vmxfile")) {
    carp "Unable to open $vmxfile: $!";
    return '';
  }
  my $line;
  while(defined($line = <$fh>)) {
    # Look for ide?:?.present and ide?:?.fileName lines.
    if($line =~ /^\s*ide\d+:\d+\.present/i) {
      my($ide, $present) = ($line =~ /^\s*(ide\d+:\d+)\.present\s*=\s*"?(\w+)"?/i);
      $diskdata{$ide}->{present} = $present;
    } elsif($line =~ /^\s*ide\d+:\d+\.filename/i) {
      my($ide, $filename) = ($line =~ /^\s*(ide\d+:\d+)\.filename\s*=\s*"?([^"]+)"?/i);
      $diskdata{$ide}->{filename} = $filename;
    }
  }
  $fh->close();
  # This makes a list of the keys of %diskdata whose 'present' value is 'true'
  # and whose 'filename' ends in .vmdk.
  my @present_keys = grep { (lc($diskdata{$_}->{present}) eq 'true') && ($diskdata{$_}->{filename} =~ /\.vmdk$/ ) } keys(%diskdata);
  my %changes = ();
  # Now, for each of those disk files, see what their createType is.  If it
  # isn't "monolithicSparse", it needs to be converted.
  foreach my $key (@present_keys) {
    my $diskfile = $diskdata{$key}->{filename};
    # If the filename doesn't have a path, assume it to be in the same
    # directory as the .vmx file.
    my $diskpath = (substr($diskfile, 0, 1) eq '/')?$diskfile:"$vmdir/$diskfile";
    my $createtype = '';
    if($fh->open("<$diskpath")) {
      while(defined($line = <$fh>)) {
	if($line =~ /^\s*createtype/i) {
	  ($createtype) = ($line =~ /^\s*createtype\s*=\s*"?(\w+)"?/i);
	  last;
	}
      }
      $fh->close();
    } else {
      carp "Unable to open $diskpath for read: $!";
      next;
    }
    unless(lc($createtype) eq 'monolithicsparse') {
      printf("Converting virtual disk $diskfile to monolithic format ...\n");
      my $drive = $driveofnode{$key};
      my $newdiskfile = "$vmname-$drive.vmdk";
      my $newdiskpath = "$vmdir/$newdiskfile";
      &test_cmd("vmware-vdiskmanager -r $diskpath -t 0 $newdiskpath");
      push(@created_files, $newdiskpath);
      $changes{"$key.fileName"} = $newdiskfile;
    }
  }
  # If we converted any disk files, change them in the .vmx file.
  if(%changes) {
    &modify_vmxfile($vmxfile, \%changes) || return '';
  }
  return \@created_files;
}

sub get_distro_from_issue {
  # Given a libguestfs object that has been added/launched/mounted, get the
  # /etc/issue file and attempt to divine the distro from it.  Needs a
  # temporary directory to download the file to.  Returns '6' (meaning RHEL 6)
  # unless we find something else we recognize.
  my($g, $tempdir) = @_;
  my $distro = '6'; # RHEL 6 unless we find otherwise
  if($g->exists('/etc/issue')) {
    $g->download('/etc/issue', "$tempdir/issue.orig");
    my $distroline = `grep -Ei '[[:space:]]+release[[:space:]]+[[:digit:]]' $tempdir/issue.orig`;
    chomp $distroline;
    my($distroname, $release) = ($distroline =~ /^(.+)\s+release\s+([\.\d]+)/i);
    my $prefix = '';
    if(lc($distroname) eq 'centos') {
      $prefix = 'c';
    }
    $distro = $prefix.$release;
  }
  return $distro;
}

sub copy_kvm_domain($$$$) {
  # Do all the various tasks required to copy a domain.  If $copy_disks is
  # true, copy the disk images, and change the system's identity to reflect the
  # new domain name (we have already ensured that the original domain is turned
  # off in this case).
  my($origvm, $newvm, $copy_disks, $distro) = @_;

  my $result = 1;
  # Create a new domain based on the old domain's XML with changes
  my $origdom = $CFG::VMM->get_domain_by_name($origvm);
  my $autostart = $origdom->get_autostart();
  # We should already have checked that the original domain existed, but just
  # in case
  die "VM $origdom doesn't exist\n" unless $origdom;
  # Get the XML
  my $xml = $origdom->get_xml_description();
  # Parse the XML
  my $t = XML::Twig->new();
  $t->parse($xml);
  # Get the domain's memory and number of CPUs
  my($oxmem) = $t->get_xpath('./memory[1]');
  my $memory = DataAmount->new($oxmem->text().$oxmem->att('unit'));
  debug_printf "%s's memory = %s", $origvm, $memory->in_min_base2_unit();
  my($oxvcpu) = $t->get_xpath('./vcpu[1]');
  my $vcpu = $oxvcpu->text();
  debug_printf "%s's CPUs = %s", $origvm, $vcpu;
  # We'll need this array in any case.
  my @odisks = $t->get_xpath('./devices/disk[@type="file"]');
  # If we're not copying the disks, get the size of /dev/vdb so we can create a
  # new disk with the same size.
  my $disksize;
  unless($copy_disks) {
    # Find the second disk.  Its filename will end in '-hdb.qcow2' by
    # convention.
    my $diskfile = undef;
    foreach my $elt (@odisks) {
      my $f = $elt->first_child('source')->att('file');
      if($f =~ /-hdb\.qcow2$/) {
	$diskfile = $f;
	last;
      }
    }
    croak "Unable to get name of ${origvm}'s /usr/local disk file" unless($diskfile);
    croak "Unable to find $diskfile" unless (-e $diskfile);
    croak "Unable to read $diskfile" unless (-r $diskfile);
    ($disksize) = grep { $_ =~ /^\s*virtual size:/i } `qemu-img info $diskfile`;
    $disksize =~ s/^\s*virtual size:\s*//i;
    $disksize =~ s/\s+.*$//;
    $disksize = DataAmount->new($disksize);
    debug_printf "%s's /usr/local size = %s", $origvm, $disksize->in_min_base10_unit();
  }
  # We now have $memory, $vcpu, and (unless $copy_disks) $disksize.

  # Now, if $copy_disks, we're going to copy the disks to new files based on
  # $newvm.  If not, we're going to get the main disk from stemcell and create
  # the other one, just as mkvm does.
  if($copy_disks) {
    foreach my $elt (@odisks) {
      my $efs = $elt->first_child('source');
      my $f = $efs->att('file');
      my $newf = $f;
      $newf =~ s/\Q$origvm\E/$newvm/;
      printf("Copying %s to %s ...\n", $f, $newf);
      if($CFG::TEST_MODE) {
	test_printf 'Copy %s to %s', $f, $newf;
      } else {
	copy($f, $newf) or croak "Copy failed: $!";
      }
      $efs->set_att('file', $newf);
    }
  } else {
    &install_stemcell($newvm);
    $t->parsefile("/tmp/$CFG::STEMCELL.xml");
    my @disks = $t->get_xpath('./devices/disk[@type="file"]');
    foreach my $elt (@disks) {
      $elt->first_child('source')->{att}->{file} =~ s/\Q$CFG::STEMCELL\E/$newvm/;
    }
    &test_cmd(sprintf('mv %s/%s-hda.qcow2 %s/%s-hda.qcow2',
		      $CFG::VM_DIR, $CFG::STEMCELL, $CFG::VM_DIR, $newvm));
    &create_vdisk_img(sprintf('%s/%s-hdb.qcow2', $CFG::VM_DIR, $newvm), $disksize, 1) || return '';
  }
  $CFG::VMM->get_storage_pool_by_name('default')->refresh();
  # We'll need these network parameters in any case.
  my $net = &lookup_network_params($newvm);
  my($xname) = $t->get_xpath('./name[1]');
  $xname->set_text($newvm);
  my($xuuid) = $t->get_xpath('./uuid[1]');
  $xuuid->set_text(&generate_uuid($newvm));
  my($xmem) = $t->get_xpath('./memory[1]');
  $xmem->set_text($memory->in('KiB'));
  my($xcmem) = $t->get_xpath('./currentMemory[1]');
  $xcmem->set_text($xmem->text());
  my($xvcpu) = $t->get_xpath('./vcpu[1]');
  $xvcpu->set_text($vcpu);
  my @interfaces = $t->get_xpath('./devices/interface[@type="bridge"]');
  foreach my $elt (@interfaces) {
    my $if = $elt->first_child('source')->att('bridge');
    $elt->first_child('mac')->set_att('address', $net->{($if eq 'br1')?'private':'public'}->{hwaddr});
  }
  if($CFG::TEST_MODE) {
    test_printf "define domain '%s'", $newvm;
    test_printf "set autostart of domain '%s' to '%s'", $newvm, $autostart;
  } else {
    my $dom = $CFG::VMM->define_domain($t->sprint());
    $dom->set_autostart($autostart);
  }
  my $tplfh = &make_temp_gocvm_file
    (
     net => $net,
     autoinstall => '',
     noautonet => '',
     called_as => $CFG::CALLED_AS,
     distro => $distro,
    );
  return '' unless $tplfh;
  my $tmpconf = $tplfh->filename;
  if($CFG::TEST_MODE) {
    test_printf 'putting /opt/etc/gocvm/mkvm.pl in place on disk image';
  } else {
    my $g = Sys::Guestfs->new();
    $g->add_domain($newvm);
    $g->launch();
    &guestfs_mount_all($g);
    $g->mkdir_p('/opt/etc/gocvm');
    $g->upload($tmpconf, '/opt/etc/gocvm/mkvm.pl');
    &guestfs_set_net_parameters($g, $net);
    my $tempdir = File::Temp::tempdir('cpvm.XXXXXXXX', DIR=>'/tmp', CLEANUP => 1);
    &guestfs_sign_ssh_key($g, $net, $tempdir);
    &guestfs_create_sign_puppet_cert($g, $net, $tempdir);
    &guestfs_setup_sudoers($g, $net, $tempdir);
    $g->umount_all();
    $g->shutdown();
    $g->close();
  }
  system("cat $tmpconf") if($CFG::DEBUG_MODE);
  $tplfh->close();
  $result = &test_cmd("rm -f /tmp/$CFG::STEMCELL.xml");
  return '' unless($result == 0);
  return 1;
}

sub rename_kvm_domain($$$) {
  # Do all the various tasks required to rename a domain.  If $deep is true, do
  # a "deep" rename: edit the system configuration files within the main disk
  # image so as to actually change the domain's internal/external network
  # hostnames and IPs.

  my($oldvm, $newvm, $deep) = @_;
  my $net = undef;
  # Even if $deep is true, if the old and new names are the same except for the
  # version number, don't do a "deep" rename, because it wouldn't really change
  # the network identity.
  if($deep) {
    my($old_wo_vers) = split(/\./, $oldvm, 2);
    my($new_wo_vers) = split(/\./, $newvm, 2);
    if($old_wo_vers eq $new_wo_vers) {
      $deep = '';
    }
  }
  if($deep) {
    # If a "deep" rename, we'll need the old and new hostnames, and their IP
    # addresses, and the hardware addresses based on them
    printf("Deep-renaming '%s' to '%s' ...\n", $oldvm, $newvm);
    my $oldhost = $oldvm;
    $oldhost =~ s/\..*$//;
    my $newhost = $newvm;
    $newhost =~ s/\..*$//;
    $net = &lookup_network_params($newvm);
    # Make sure nothing's listening on either of those IPs already
    my $p = Net::Ping->new('icmp', 2);
    die("$net->{public}->{hostname} exists on the network ... exiting") if $p->ping($net->{public}->{hostname});
    die("$net->{private}->{hostname} exists on the network ... exiting") if $p->ping($net->{private}->{hostname});
  }
  # Create a new domain based on the old domain's XML with changes
  my $olddom = $CFG::VMM->get_domain_by_name($oldvm);
  # We should already have checked that the original domain existed, but just
  # in case
  die("VM $olddom doesn't exist\n") unless $olddom;
  # Get autostart flag, which isn't stored in XML
  my $autostart = $olddom->get_autostart();
  # Get the XML
  my $xml = $olddom->get_xml_description();
  # Parse the XML
  my $t = XML::Twig->new();
  $t->parse($xml);
  # Change the domain's name
  my($name) = $t->get_xpath('./name[1]');
  die("Unable to find a domain name in XML\n") unless $name;
  $name->set_text($newvm);
  # Change its UUID
  my($uuid) = $t->get_xpath('./uuid[1]');
  $uuid->set_text(&generate_uuid($newvm));
  # Change the disk file names (and save the old and new filenames so we can
  # actually change the filenames later)
  my %disk_file_rename = ();
  foreach my $disk_elt ($t->get_xpath('./devices/disk[@type="file"]')) {
    my $source_elt = $disk_elt->first_child('source');
    next unless defined $source_elt;
    my $sourceatt = $source_elt->{att};
    my $oldfile = $sourceatt->{file};
    $sourceatt->{file} =~ s/\Q$oldvm\E/$newvm/;
    $disk_file_rename{$oldfile} = $sourceatt->{file};
  }
  if($deep) {
    # If this is a "deep" rename, change the hardware addresses of the network
    # adapters.  We'll also be changing the config files within the disks to
    # match.
    foreach my $int_elt ($t->get_xpath('./devices/interface[@type="bridge"]')) {
      my $if = $int_elt->first_child('source')->{att}->{bridge};
      $int_elt->first_child('mac')->{att}->{address} = $net->{($if eq 'br1')?'private':'public'}->{hwaddr};
    }
  }
  # Define the new domain
  if($CFG::TEST_MODE) {
    test_printf "create new domain '%s'", $newvm;
    test_printf "setting autostart of '%s' to '%s'", $newvm, $autostart;
  } else {
    my $newdom = $CFG::VMM->define_domain($t->sprint);
    croak("Unable to define new domain '$newvm'") unless $newdom;
    $newdom->set_autostart($autostart);
  }
  if($deep) {
    # If a "deep" rename, use libguestfs to alter the network configuration
    # within the main disk image.
    if($CFG::TEST_MODE) {
      test_printf 'make changes to guest filesystem to reflect new network identity';
    } else {
      my $g = Sys::Guestfs->new();
      $g->add_domain($oldvm);
      $g->launch();
      &guestfs_mount_all($g);
      &guestfs_set_net_parameters($g, $net);
      # We'll want to make a new /opt/etc/gocvm/mkvm.pl file with the new
      # parameters.  In order to do that, we'll have to get the non-networking
      # parameters from the old mkvm.pl file (if it exists) so they can be
      # copied to the new one unchanged.  Whee.
      my $tplfh;
      my $tempdir = File::Temp::tempdir('mvvm.XXXXXXXX', DIR => '/tmp', CLEANUP => 1);
      if($g->exists('/opt/etc/gocvm/mkvm.pl')) {
	$g->download('/opt/etc/gocvm/mkvm.pl', "$tempdir/mkvm.pl.orig");
	my $mkvm_orig = &read_temp_gocvm_file("$tempdir/mkvm.pl.orig");
	if($mkvm_orig) {
	  debug_printf "distro from old mkvm.pl file: %s", defined($mkvm_orig->{distro})?$mkvm_orig->{distro}:'(undef)';
	  $tplfh = &make_temp_gocvm_file
	    (
	     net => $net,
	     autoinstall => $mkvm_orig->{autoinstall},
	     noautonet => $mkvm_orig->{noautonet},
	     called_as => $CFG::CALLED_AS,
	     distro => $mkvm_orig->{distro},
	    );
	}
      } else {
	# There was no mkvm.pl file on the existing VM.  Act as if there was
	# (there may be no distro, however).  Try to get the distro.
	$tplfh = &make_temp_gocvm_file
	  (
	   net => $net,
	   autoinstall => '',
	   noautonet => '',
	   called_as => $CFG::CALLED_AS,
	   distro => &get_distro_from_issue($g, $tempdir),
	  );
      }
      #system("cat ".$tplfh->filename) if($CFG::DEBUG_MODE);
      $g->mkdir_p('/opt/etc/gocvm') unless $g->exists('/opt/etc/gocvm');
      $g->upload($tplfh->filename, '/opt/etc/gocvm/mkvm.pl');
      # Sign the VM's SSH key.
      &guestfs_sign_ssh_key($g, $net, $tempdir);
      # Get a Puppet certificate for the VM.
      &guestfs_create_sign_puppet_cert($g, $net, $tempdir);
      # Set up initial sudoers settings.
      &guestfs_setup_sudoers($g, $net, $tempdir);
      $g->umount_all();
      $g->shutdown();
      $g->close();
    }
  }
  # Once we're sure everything's OK, rename the disk files and undefine the old
  # domain (we know we can get away with letting it exist this long because
  # we've made sure the new domain's name is different from the old one's).
  if($CFG::TEST_MODE) {
    test_printf 'Rename disk images and undefine old domain';
  } else {
    while(my($oldpath, $newpath) = each(%disk_file_rename)) {
      croak("Unable to rename '$oldpath' to '$newpath': $!") unless rename $oldpath, $newpath;
    }
    $olddom->undefine();
  }
}

sub rename_vmware_vm($$) {
  # Rename a VMware VM.  Usually called by do_mvvm().

  my($oldname, $newname) = @_;
  # Tell VMware to forget about this VM under its old name.
  &unregister_vm($oldname);
  chdir($CFG::VM_DIR);
  if($CFG::VM_HOST_TYPE eq 'vmw') {
    # Unmount the VM under its old name
    &test_cmd("umount $oldname");
    # Generate the new filesystem label
    my $vm_ext2_label = &make_ext2_label($newname);
    # Change the filesystem label
    &test_cmd("e2label /dev/$CFG::VM_VG/$oldname $vm_ext2_label");
    # Change the line in /etc/fstab -- replace line with sed
    &test_cmd("sed -i.bak -re '!^[^[:space:]]+[[:space:]]+$CFG::VM_DIR/$oldname/?[[:space:]]!cLABEL=$vm_ext2_label	$CFG::VM_DIR/$newname	ext3	defaults	1 2' /etc/fstab");
    # Deactivate the LV
    &test_cmd("lvchange -a n /dev/$CFG::VM_VG/$oldname");
    # Rename the LV
    &test_cmd("lvrename $CFG::VM_VG $oldname $newname");
    # Reactivate the LV
    &test_cmd("lvchange -a y /dev/$CFG::VM_VG/$newname");
  }
  # Change the mount point or directory's name
  &test_cmd("mv $oldname $newname");
  if($CFG::VM_HOST_TYPE eq 'vmw') {
    # Remount the LV
    &test_cmd("mount $newname");
  }
  chdir("$CFG::VM_DIR/$newname");
  # Change the .vmx file's name
  &test_cmd("mv $oldname.vmx $newname.vmx");
  # Change the displayname within the .vmx file
  &test_cmd("sed -i.bak -re '/^[[:space:]]*displayname[[:space:]]*=[[:space:]]*\"/IcdisplayName = \"$newname\"' $newname.vmx");
  # Tell VMware to open the VM under its new name
  &register_vm($newname);
  # Set the owner/group/permissions of the files, just to make sure
  &set_owners_perms("$CFG::VM_DIR/$newname");
}

sub tarball_kvm_files($$) {
  # Given a filename, create a tarball of the $vmname VM's necessary files.

  # This means creating an .xml dump of the VM's metadata using
  # Sys::Virt::Domain->get_xml_description and discovering all virtual disk
  # files referred to in it.

  my($vmname, $tarballpath) = @_;
  my $xml = $CFG::VMM->get_domain_by_name($vmname)->get_xml_description();
  # Have XML::Twig parse the XML text.
  my $t = XML::Twig->new();
  $t->parse($xml);
  my $result;
  # Discover the disk images from that .xml file using XML::Twig.
  my @disk_image_paths = ();
  if($CFG::TEST_MODE) {
    @disk_image_paths = ('/var/lib/libvirt/testvm-hda.qcow2', '/var/lib/libvirt/testvm-hdb.qcow2');
  } else {
    my @elts = $t->get_xpath('//disk/source[@file]');
    foreach my $elt (@elts) {
      # Quick and dirty excluder for virtual disk images residing on /net --
      # this was originally because of the multi-terabyte image files stored on
      # the NAS device because of OASIS. -- TJL 2014-03-24
      next if($elt->{att}->{file} =~ m!^/net!);
      push(@disk_image_paths, $elt->{att}->{file});
    }
  }
  # Write the XML to the temporary file, /tmp/$vmname.xml, so it can go
  # into the tarball along with the disk images.
  my $fh = IO::File->new(">/tmp/$vmname.xml");
  croak("Unable to open /tmp/$vmname.xml for writing: $!") unless defined($fh);
  $t->set_pretty_print('indented');
  $t->print($fh);
  $fh->close();
  # Make the tarball.
  $result = &make_tarball(
		     file => $tarballpath,
		     chdir => '/',
		     include => [
				 "/tmp/$vmname.xml",
				 @disk_image_paths,
				],
		    );
  return $result;
}

sub tarball_vmware_files($$) {
  # Given a filename, create a tarball of the $vmname VM's necessary files.

  # This means the .vmx file, the .vmsd file if any, the nvram file if any,
  # and:

  # any active snapshots' .vmem and .vmsn files
  # the main .vmdk file for all active disks
  # any subsidiary .vmdk files for active disks
  # the main .vmdk file for all snapshots
  # any subsidiary .vmdk files for all snapshots

  # Procedure: Go to the .vmx file and find all present disks' filenames.
  # Go to the .vmsd file and find all snapshots' disk filenames.
  # For each disk,
  #  look at its createtype
  #  if it is twoGbMaxExtent, find all its subsidiary files

  my($vmname, $tarballpath) = @_;
  my $vmdir = "$CFG::VM_DIR/$vmname";
  my $fh = IO::File->new();
  my $line;
  # Go through the .vmx file.
  my $vmxfile = "$vmname.vmx";
  my $vmxpath = "$vmdir/$vmxfile";
  unless($fh->open("<$vmxpath")) {
    carp "Unable to open $vmxpath: $!";
    return '';
  }
  my @files = ($vmxfile);
  my %diskdata = ();
  my %disk_file_found = ();
  my @disk_files = ();
  while(defined($line = <$fh>)) {
    if($line =~ /^\s*ide\d+:\d+\./i) {
      chomp($line);
      next if($line eq '');
      my($node, $subparam, $value) = ($line =~ /^\s*(ide\d+:\d+)\.([^\s=]+)\s*=\s*"?([^\s"]*)"?/i);
      $subparam = lc($subparam);
      $diskdata{$node}->{$subparam} = $value;
    }
  }
  $fh->close();
  # Put all present disk files in the list.
  foreach my $node (keys(%diskdata)) {
    if(lc($diskdata{$node}->{present}) eq 'true') {
      if($diskdata{$node}->{filename} =~ /\.vmdk$/) {
	push(@disk_files, $diskdata{$node}->{filename});
	$disk_file_found{$diskdata{$node}->{filename}} = 1;
      } else { # Other types of file, like .isos, or partitions or LVs, we must ignore
	$diskdata{$node}->{present} = 'FALSE';
	&modify_vmxfile($vmxpath, {"$node.present" => 'FALSE'});
      }
    }
  }
  # Go through the .vmsd file.
  my $vmsdfile = "$vmname.vmsd";
  my $vmsdpath = "$vmdir/$vmsdfile";
  if($fh->open("<$vmsdpath")) {
    push(@files, $vmsdfile);
    my %ssdata = ();
    my $ssnum = 0;
    my $sscurrent = 0;
    while(defined($line = <$fh>)) {
      if($line =~ /^\s*snapshot\.numsnapshots/i) {
	($ssnum) = ($line =~ /^\s*snapshot\.numsnapshots\s*=\s*"?(\d+)"?/i);
       	if($ssnum == 0) {
	  # No snapshots -- might as well quit
	  last;
	}
      } elsif($line =~ /^\s*snapshot\.current/i) {
	($sscurrent) = ($line =~ /^\s*snapshot\.current\s*=\s*"?(\d+)"?/i);
      } elsif($line =~ /^\s*snapshot\d+\./i) {
	my($index, $subparam, $value) = ($line =~ /^\s*snapshot(\d+)\.([^\s=]+)\s*=\s*"?([^\s"]+)"?/i);
	$subparam = lc($subparam);
	$ssdata{$index}->{$subparam} = $value;
      }
    }
    $fh->close();
    if($ssnum > 0) {
      # Rearrange %ssdata so the UID is the key
      my %ssdatabyuid = ();
      foreach my $index (keys(%ssdata)) {
	my $uid = $ssdata{$index}->{uid};
	$ssdatabyuid{$uid} = $ssdata{$index};
      }
      # Follow the chain of snapshots
      my $uid = $sscurrent;
      while(1) {
	# Get the .vmsn and .vmem files
	my $vmsnfile = $ssdatabyuid{$uid}->{filename};
	my $vmemfile = $vmsnfile;
	$vmemfile =~ s/\.vmsn$/.vmem/;
	push(@files, $vmsnfile, $vmemfile);
	# Get the filenames of all disk files
	my $diskindex = 0;
	while($diskindex < $ssdatabyuid{$uid}->{numdisks}) {
	  my $prefix = 'disk'.$diskindex;
	  my $filenameparam = $prefix.'.filename';
	  my $diskfile = $ssdatabyuid{$uid}->{$filenameparam};
	  unless($disk_file_found{$diskfile}) {
	    push(@disk_files, $diskfile);
	    $disk_file_found{$diskfile} = 1;
	  }
	  ++$diskindex;
	}
	last unless exists($ssdatabyuid{$uid}->{parent});
	$uid = $ssdatabyuid{$uid}->{parent};
      }
    }
  } else {
    carp "Unable to open $vmsdpath: $!";
  }
  # Now go through the disk files and pick up any subsidiary files there may
  # be.

  # Subsidiary files are only of interest if the createType is not
  # monolithicSparse.  If the createType is that, don't bother looking for
  # them.  There will be an extent line, but it will just refer back to the
  # same disk file.  What's more, that's the only type where the entire disk is
  # all in one file -- even monolithicFlat files store their metadata in the
  # main .vmdk file and then have a subsidiary file (albeit a single one) for
  # the disk data.  We don't want to go reading through a monolithicSparse
  # file's disk data; once we find that createType, we're done.

  # Extent lines look like this:

  # RW 123456 SPARSE "filename" 0

  # I've never seen anything other than RW for the first field.  The second
  # field is the size.  The third field is either SPARSE or FLAT.  The fourth
  # field is the filename holding this extent's data.  I don't know what the
  # fifth field is, but it only appears in twoGbMaxExtentFlat disks.
  foreach my $mainfile (keys(%disk_file_found)) {
    my $mainpath = "$vmdir/$mainfile";
    my $createtype = '';
    if($fh->open("<$mainpath")) {
      while(defined($line = <$fh>)) {
	if($line =~ /^\s*createtype/i) {
	  ($createtype) = ($line =~ /^\s*createtype\s*=\s*"?(\w+)"?/i);
	  $createtype = lc($createtype);
	  # If it's monolithicSparse we don't need any more info
	  last if($createtype eq 'monolithicsparse');
	} elsif($line =~ /^\s*\w+\s+\d+\s+\w+\s+"?[^\s"]+"?/) {
	  my($diskfile) = ($line =~ /^\s*\w+\s+\d+\s+\w+\s+"?([^\s"]+)"?/);
	  unless($disk_file_found{$diskfile}) {
	    push(@disk_files, $diskfile);
	    $disk_file_found{$diskfile} = 1;
	  }
	}
      }
      $fh->close();
    }
  }
  # Add the nvram file to @files, if it exists.
  if(-e "$vmdir/nvram") {
    push(@files, 'nvram');
  }
  # Add the disk files to the end of @files.
  push(@files, sort(@disk_files));
  # We should now have in @files a complete list of all the files necessary to
  # archive the VM.  Any leftover files from old snapshots, previous versions
  # of converted disks, etc. won't be in the list and won't get included.
  printf("Now exporting the following files into %s:\n", $tarballpath);
  foreach my $file (@files) {
    printf("%s\n", $file);
  }
  my $result = &make_tarball(
			file => $tarballpath,
			chdir => $CFG::VM_DIR,
			include => [
				    join(' ',
					 map { $vmname.'/'.$_ } @files)
				   ],
		       );
  return $result;
}

###############################################################################
# Command handlers
###############################################################################

sub do_allvm {
  # Basically this just runs the vmware-cmd or virsh command on all vms on the
  # system, which is something I found myself doing a lot by hand

  # Ensure rootitude
  if($ENV{USER} ne 'root') {
    die("Must be root.\n");
  }
  # Make sure there's a command
  my $cmd = shift(@ARGV);
  unless($cmd) {
    &main::HELP_MESSAGE();
    exit 1;
  }
  # Get args
  my @args = @ARGV;
  # Execute command based on VM host type
  if($CFG::KVM) {
    foreach my $dom ($CFG::VMM->list_all_domains()) {
      my $domname = $dom->get_name();
      printf("%s ", $domname);
      &test_cmd(sprintf("virsh %s %s", join(' ', $cmd, @args), $domname));
    }
  } else {
    foreach my $vm (`vmware-cmd -l`) {
      printf("%s ", $vm);
      &test_cmd(sprintf("vmware-cmd %s %s", $vm, join(' ', $cmd, @args)));
    }
  }
}

sub do_autovm($) {
  # Set the given VM to autostart (if it exists) if called as 'autovm', or not
  # to autostart if called as 'noautovm'.
  my($vmname) = @_;
  $vmname ||= $ARGV[0];
  unless(&vm_name_exists($vmname, 1)) {
    warn "Unable to proceed.\n";
    if($vmname eq '') {
      &main::HELP_MESSAGE();
    }
    exit 1;
  }
  my $autostart = undef;
  if($CFG::CALLED_AS eq 'autovm') {
    $autostart = 1;
  } elsif($CFG::CALLED_AS eq 'noautovm') {
    $autostart = 0;
  } else {
    # Paranoid programming.
    croak "SHOULDN'T HAPPEN";
  }
  if($CFG::KVM) {
    my $dom = get_domain_by_name $vmname;
    if(defined $dom) {
      $dom->set_autostart($autostart);
      printf "VM '%s' set to%s autostart.\n", $vmname,
	($autostart?'':' NOT');
      autostart_ask $vmname;
    } else {
      # This would be really odd, as we checked before to make sure it exists.
      carp "VM '$vmname' doesn't exist (but it did a moment ago).";
      warn "Unable to proceed.\n";
    }
  } else {
    warn "Not currently implemented.\n";
  }
}

sub do_buildvm($) {
  # Make a VM using PXE booting and Anaconda, rather than by copying stemcell.

  unless($ENV{USER} eq 'root') {
    die("Must be root.\n");
  }

  if($CFG::KVM) {
    unless(&have_x11()) {
      die("Creating VMs requires X11.  Be sure it is enabled.\n");
    }
  }

  #$CFG::VM_NAME = $ARGV[0];
  my $vmname = $ARGV[0];

  # Test the proposed name.
  unless(&vm_name_ok($vmname)) {
    warn "Unable to proceed.";
    if($vmname eq '') {
      &main::HELP_MESSAGE();
    }
    exit 1;
  }

  # Test the proposed size of the VM, including the /usr/local disk.
  unless(&have_enough_space()) {
    die("Unable to proceed.\n");
  }

  # If you can think of any more reasons why we shouldn't go ahead and make the
  # VM, put them before this point

  # Make a landing zone for the VM
  &prepare_vm_home($vmname);

  # Put the VM there
  &build_vm_pxe_anaconda($vmname);

  # Check the autostart status
  autostart_ask $vmname;
}

sub do_cpvm($$) {
  # Copy a VM's parameters to a new VM.  This means the memory, CPUs, and
  # /dev/vdb disk size.  If $CFG::CPVM_COPY_DISKS is set, we're copying the
  # virtual disk files of the existing VM (which means that VM must be off; if
  # it's running, error out).  If not, we're creating a new VM with the
  # parameters from the existing one.

  # Check for rootness
  if($ENV{USER} ne 'root') {
    die("Must be root.\n");
  }
  # Get the old and new VM names.
  #($CFG::CPVM_ORIG_NAME, $CFG::CPVM_NEW_NAME) = @ARGV;
  my($origname, $newname) = @ARGV;
  # Make sure old and new names differ
  die("The new name can't be the same as the old name.\n") if($origname eq $newname);
  # Make sure the old VM exists
  unless(&vm_name_exists($origname, 1)) {
    warn "Unable to proceed.";
    if($origname eq '') {
      &main::HELP_MESSAGE();
    }
    exit 1;
  }
  # Test the proposed new name.
  unless(&vm_name_ok($newname)) {
    warn "Unable to proceed.";
    if($newname eq '') {
      &main::HELP_MESSAGE();
    }
    exit 1;
  }
  # If $CFG::CPVM_COPY_DISKS is set, make sure the original VM is down.
  my $restart_after = '';
  if($CFG::CPVM_COPY_DISKS && &vm_running($origname)) {
    &do_stop($origname);
    $restart_after = 1;
  }

  # If you can think of any more reasons why we shouldn't go ahead and copy
  # the VM, put them before this point

  if($CFG::KVM) {
    &copy_kvm_domain($origname, $newname, $CFG::CPVM_COPY_DISKS, $CFG::DISTRO);
  } else {
    printf("cpvm not yet implemented for VMware\n");
  }
  &do_start($origname) if($restart_after);
  &do_start($newname) if($CFG::START);
  autostart_ask $newname;
}

sub do_exportvm {
  # Create a tarball containing all the VM's files -- simplifying if necessary
  # for faster import.  If $CFG::NO_SNAPSHOT_MERGE is true (-s option), don't
  # merge snapshots before export (if there are any snapshots, this will result
  # in a nonportable export, though); if there are no snapshots, this setting
  # doesn't matter.  If $CFG::NO_DISK_CONVERT is true (-c option), don't
  # convert split disks to monolithic before export (again, if there are any
  # split disks, this option will result in a nonportable export); if there are
  # no split disks (or if this is a KVM host), this setting doesn't matter.  If
  # the user seems to want to convert disk formats without first merging
  # snapshots, say that makes no sense and exit.

  # Get the VM name.
  #$CFG::VM_NAME = $ARGV[0];
  my $vmname = $ARGV[0];

  # Test the proposed name.
  if(!defined($vmname) || ($vmname eq '')) {
    warn "No VM name given.";
    &main::HELP_MESSAGE();
    warn "Unable to proceed.";
    return '';
  }
  unless(&vm_name_exists($vmname, 1)) {
    warn "Unable to proceed.";
    return '';
  }

  # If the VM is running, check for the -o option: if it's there, shut down the
  # VM before proceeding and remember to restart it afterwards.  Otherwise,
  # just warn and refuse to proceed.
  my $restart_after = '';
  if(&vm_running($vmname)) {
    &do_stop($vmname);
    $restart_after = 1;
  }

  # Decide the name and location of the export tarball.
  my $vmtype_suffix = ($CFG::KVM)?'kvm':'vmw';
  my $export_path = '';
  if($CFG::EXPORT_FILENAME) {
    # We want this to work "as expected," meaning "like other Unix utilities."
    # This means that if what's given to the -f command-line option (which is
    # $CFG::EXPORT_FILENAME) is:
    #
    # * Nothing: make up a name and write the tarball in the CWD.
    # * Relative path to a directory: make up a name and save it in that directory relative to the CWD.
    # * Absolute path to a directory: make up a name and save it in that directory.
    # * Relative path to a file: save it in that file relative to the CWD.
    # * Absolute path to a file: save it in that file.
    # * Relative path to a symlink to a directory: resolve path relative to CWD; make up a name and save it there.
    # * Absolute path to a symlink to a directory: resolve path; make up a name and save it there.

    # If we're given an absolute or relative path to an existing directory (or
    # to a symlink to an existing directory), generate the fiename and use that
    # path. The Cwd::realpath function resolves the path if there are any
    # symlinks.
    if(-d realpath($CFG::EXPORT_FILENAME)) {
      my $realpath = realpath($CFG::EXPORT_FILENAME);
      $export_path = sprintf("%s/%s.%s.tgz", $realpath, $vmname, $vmtype_suffix);
    } else {
      # What we've got either isn't an existing file or is an existing file
      # that isn't a directory or symlink.
      $export_path = sprintf("%s/%s", cwd(), $CFG::EXPORT_FILENAME);
    }
  } else {
    # If no filename was specified at all, generate the filename and put it in
    # the CWD.
    $export_path = sprintf("%s/%s.%s.tgz", cwd(), $vmname, $vmtype_suffix);
  }

  if($CFG::KVM) {
    &tarball_kvm_files($vmname, $export_path);
  } else { # VMware case
    my $files = [];
    my $vmdir = "$CFG::VM_DIR/$vmname";
    my $vmxfile = "$vmdir/$vmname.vmx";
    # Merge snapshots if necessary.
    my $snapshots = &detect_vmware_snapshots($vmname);
    if($snapshots && !$CFG::NO_SNAPSHOT_MERGE) {
      &merge_vmware_snapshots($vmname);
    }
    # Backup the .vmx file.
    my $tempvmx = File::Temp::tempnam($vmdir, "exportvm_temp_XXXXXXXX.vmx");
    return '' unless(&test_cmd("cp -p $vmxfile $tempvmx") == 0);
    unless($CFG::NO_DISK_CONVERT) {
      # If the user specified not to merge snapshots but didn't specify not to
      # convert the disks, and if there are snapshots, we can't convert the
      # disks.
      if($snapshots && $CFG::NO_SNAPSHOT_MERGE) {
	warn <<"EOF";
Warning: Snapshots exist, but you specified not to merge them.
This means I can't convert the disks, which you didn't specify not to do.
Proceeding without converting disks.  This will result in a larger export file,
and you will not be able to import this VM onto anything but a VMware host.
EOF
;
      } else {
	$files = &convert_vmware_disks($vmname);
	return '' if($files eq '');
      }
    }
    # Now tarball the files.
    &tarball_vmware_files($vmname, $export_path);
    # Clean up and restore the .vmx file from backup.
    foreach my $path (@$files) {
      return '' unless(&test_cmd("rm -f $path") == 0);
    }
    return '' unless(&test_cmd("mv $tempvmx $vmxfile") == 0);
  }
  &do_start($vmname) if($restart_after);
  return 1;
}

sub do_importvm {
  # Given a tarball created by do_exportvm (see above), import that VM onto the
  # host.  First we'll have to figure out what it is, so unpack it into a
  # temporary directory to examine its files.  If this is a cross-platform
  # import (i.e. if the exported tarball was created on VMware and this is a
  # KVM host or vice-versa), make sure it's ready for import -- if there's a
  # VMware split disk or snapshot present, we can't import into KVM.  Make sure
  # that the name of the new VM (determined from the $CFG::IMPORT_NAME variable
  # or from the files) doesn't conflict with an existing VM on this host.  Then
  # convert the disks if necessary, modify the definition file if necessary,
  # move things to their appropriate places, and add the VM to the host.

  # Remember how the tarballs are structured:

  # VMware: <vm name>/<vm name>.vmx
  #	    <vm name>/<vm name>.vmsd
  #	    <vm name>/nvram
  #	    <vm name>/<drive>.vmdk
  #	    <vm name>/...

  # KVM: tmp/<vm name>.xml
  #	 var/lib/libvirt/images/<vm name>-<drive>.qcow2
  #	 var/lib/libvirt/images/...

  # Get the filename.
  $CFG::IMPORT_FILE = $ARGV[0];

  # Make sure it exists and is readable.
  unless($CFG::IMPORT_FILE) {
    &main::HELP_MESSAGE();
    exit 1;
  }
  unless(-e $CFG::IMPORT_FILE) {
    die("File $CFG::IMPORT_FILE does not exist.\n");
  }
  unless(-r $CFG::IMPORT_FILE) {
    die("Unable to read $CFG::IMPORT_FILE.\n");
  }
  # If we're still here, there's a file and it's readable.

  # Unpack it to a temporary directory.
  my $tempdir = File::Temp::tempdir('importvm.XXXXXXXX', DIR => "$CFG::VM_DIR", CLEANUP => 1);
  printf("Unpacking tarball ...\n");
  &test_cmd("tar zxf $CFG::IMPORT_FILE -C $tempdir");

  # Determine type of exported tarball we're importing.
  my $import_type = '';
  if($CFG::TEST_MODE) {
    # We haven't actually unpacked anything, so just pick something from the
    # filename so the test can proceed.
    if($CFG::IMPORT_FILE =~ /\.vmw\./) {
      $import_type = 'vmw';
    } else {
      $import_type = 'kvm';
    }
  } else {
    # If there's a */*.vmx file, it's a VMware tarball.  If there's a tmp/*.xml
    # file, it's a KVM tarball.  Primitive, but I hope it works.
    if(defined(<$tempdir/*/*.vmx>) && (-e <$tempdir/*/*.vmx>)) {
      $import_type = 'vmw';
    } elsif(defined(<$tempdir/tmp/*.xml>) && (-e <$tempdir/tmp/*.xml>)) {
      $import_type = 'kvm';
    }
    unless($import_type) {
      &test_cmd("rm -rf $tempdir");
      die("Archive $CFG::IMPORT_FILE does not appear to be either VMware or KVM.\n");
    }
  }
  # If we're still here, the VM files from the tarball are in $tempdir, and
  # $import_type is either 'vmw' or 'kvm'.

  # Now there are 4 options: kvm-to-kvm, vmware-to-kvm, vmware-to-vmware, and
  # kvm-to-vmware.
  if($import_type eq 'kvm') { # KVM -> *
    # First we need to know the XML file's name, and from that, we need the VM
    # (domain) name.
    my $xmlfile = '';
    if($CFG::TEST_MODE) {
      # Just make up a filename to test with.
      $xmlfile = 'testvm.xml';
    } else {
      # Get the VM name from the .xml file (first find the .xml file)
      my %dir;
      tie %dir, 'IO::Dir', "$tempdir/tmp";
      # Find the first .xml file in the directory.
      ($xmlfile) = grep { /\.xml$/ } keys(%dir);
      unless($xmlfile) {
	die("Somehow there was no .xml file in $tempdir/tmp\n");
      }
      unless(-r "$tempdir/tmp/$xmlfile") {
	die("Unable to read $xmlfile -- insufficient permissions\n");
      }
      untie %dir;
    }
    if($CFG::KVM) { # KVM -> KVM case
      # Just import the KVM VM.  We will need the virtual disk file names.
      my $t = XML::Twig->new();
      $t->parsefile("$tempdir/tmp/$xmlfile");
      my @vols = ();
      if($CFG::TEST_MODE) {
	# For testing, just make up some nonexistent files.
	@vols = (
		 "/var/lib/libvirt/images/testvm-hda.qcow2",
		 "/var/lib/libvirt/images/testvm-hdb.qcow2",
		);
      } else {
	# Get the virtual disk file names from the XML file.
	my @elts = $t->get_xpath('//disk/source[@file]');
	foreach my $elt (@elts) {
	  push(@vols, $elt->{att}->{file});
	}
      }
      # Move those files to $CFG::VM_DIR.
      foreach my $vol (@vols) {
	&test_cmd("mv $tempdir/$vol $CFG::VM_DIR");
      }
      # And set up the VM based on the XML file.
      my $dom = $CFG::VMM->define_domain($t->sprint());
      $CFG::IMPORT_NAME ||= $dom->get_name();
      # Set the new VM host in the /opt/etc/gocvm/mkvm.pl file.  If that file
      # exists, reading it with &read_temp_gocvm_file and then writing it with
      # &make_temp_gocvm_file will update it.  If it doesn't exist, we'll have
      # to make one up.
      my $g = Sys::Guestfs->new();
      $g->add_domain($CFG::IMPORT_NAME);
      $g->launch();
      &guestfs_mount_all($g);
      $g->mkdir_p('/opt/etc/gocvm') unless $g->exists('/opt/etc/gocvm');
      if($g->exists('/opt/etc/gocvm/mkvm.pl')) {
	$g->download('/opt/etc/gocvm/mkvm.pl', "$tempdir/mkvm.pl");
	my $mkvm_orig = &read_temp_gocvm_file("$tempdir/mkvm.pl");
	my $tplfh = &make_temp_gocvm_file(%$mkvm_orig);
	$g->upload($tplfh->filename, '/opt/etc/gocvm/mkvm.pl');
      } else {
	my $tplfh = &make_temp_gocvm_file
	  (
	   net => &lookup_network_params($CFG::IMPORT_NAME),
	   autoinstall => '',
	   noautonet => '',
	   called_as => $CFG::CALLED_AS,
	   distro => &get_distro_from_issue($g, $tempdir),
	  );
	$g->upload($tplfh->filename, '/opt/etc/gocvm/mkvm.pl');
      }
      $g->umount_all();
      $g->shutdown();
      $g->close();
    } else { # KVM -> VMware case
      # The problem here is with the hardware addresses.  We must change the virtual
      # Ethernet adapters to have hardware addresses in the VMware range instead of
      # the KVM range, meaning we'd have to use libguestfs to do this on the
      # KVM disk files before conversion.  This all exists for RHEL5, so it
      # could be done, but I haven't had the impetus to make this happen.  What
      # few KVM to VMware conversions I've done have all been by hand, because
      # it's so rare.

      # Besides, soon there won't be any need for this conversion.
      printf("(KVM -> VMware import not yet implemented)\n");
    }
  } else { # VMware -> *
    # Find the .vmx file
    my $vmdir = '';
    my $vmxfile = '';
    if($CFG::TEST_MODE) {
      # Make up a directory and file for testing.
      $vmdir = 'testvm';
      $vmxfile = 'testvm.vmx';
    } else {
      # Find the directory and .vmx file.
      my %dir;
      tie %dir, 'IO::Dir', "$tempdir";
      # Find the first subdirectory of $tempdir that isn't . or .. (there
      # should only be one)
      foreach my $file (grep { $_ !~ /^\.+$/ } keys(%dir)) {
	# This magic just comes from experimenting with the mode output
	if(($dir{$file}->mode >> 12) == 4) {
	  $vmdir = $file;
	  last;
	}
      }
      unless($vmdir) {
	die("Somehow there was no subdirectory in $tempdir\n");
      }
      untie %dir;
      tie %dir, 'IO::Dir', "$tempdir/$vmdir";
      # Find the first .vmx file in that directory.
      ($vmxfile) = grep { /\.vmx$/ } keys(%dir);
      unless($vmxfile) {
	die("Somehow there was no .vmx file in $tempdir/$vmdir\n");
      }
      unless(-r "$tempdir/$vmdir/$vmxfile") {
	&test_cmd("ls -lha $tempdir/$vmdir");
	die("Unable to read $vmxfile -- insufficient permissions\n");
      }
      untie %dir;
    }

    # Read the data from the .vmx file.
    my($kwref, $vmxref) = &read_vmxfile("$tempdir/$vmdir/$vmxfile");

    # Give some default values in case they're not given in the file
    # (surprisingly, at least numvcpus is sometimes not set; perhaps this
    # happens to others too)
    $vmxref->{numvcpus_val} ||= 1;
    $vmxref->{memsize_val} ||= 1024;

    # Get the VM name, unless $CFG::IMPORT_NAME is already set
    $CFG::IMPORT_NAME ||= $vmxref->{'displayname_val'};

    # If there's a problem with the name, stop now
    unless(&vm_name_ok($CFG::IMPORT_NAME)) {
      warn "Unable to proceed.";
      &test_cmd("rm -rf $tempdir");
      exit 1;
    }

    # Decide whether conversion must be done
    if($CFG::KVM) { # VMware -> KVM
      # Start constructing the virt-install command
      my $cmd = <<"EOF"
virt-install --import --os-type=linux --os-variant=rhel5.4 --noautoconsole
  --noreboot -k en_us -n $CFG::IMPORT_NAME
EOF
	;
      # VMWare and libvirt both measure RAM in MiB.
      $cmd .= sprintf(' -r %d', $vmxref->{memsize_val});
      # Number of CPUs.
      $cmd .= sprintf(' --vcpus %d', $vmxref->{numvcpus_val});
      # Get the list of virtual disk files
      my @ides = grep { # Only the keys that have .present = 'TRUE'
	$vmxref->{$_}->{present_val} eq 'TRUE'
      } grep { # Just the ideX:Y keys
	/^ide\d+:\d+_ref$/
      } keys(%$vmxref);
      # Convert each disk file
      my %drive =
	(
	 'ide0:0_ref' => 'hda',
	 'ide0:1_ref' => 'hdb',
	 'ide1:0_ref' => 'hdc',
	 'ide1:1_ref' => 'hdd',
	);
      foreach my $ide (sort(@ides)) {
	my $src_filename = sprintf("%s/%s/%s", $tempdir, $vmdir,
				   $vmxref->{$ide}->{filename_val});
	my $dest_filename = sprintf("%s/%s-%s.qcow2", $CFG::VM_DIR,
				    $CFG::IMPORT_NAME, $drive{$ide});
	printf("Converting %s to %s ...\n",
	       $vmxref->{$ide}->{filename_val},
	       $dest_filename);
	&convert_vmware_img_to_kvm($src_filename, $dest_filename);
	$cmd .= sprintf(' --disk path="%s",bus=virtio,format=qcow2,cache=none',
			$dest_filename);
      }
      # Ethernet interfaces.
      foreach my $ifnum (0, 1) {
	my $ethernet = 'ethernet'.$ifnum;
	if($vmxref->{$ethernet."_ref"}->{present_val} eq 'TRUE') {
	  my $hwaddr = $vmxref->{$ethernet."_ref"}->{address_val} || $vmxref->{$ethernet."_ref"}->{generatedaddress_val};
	  $hwaddr =~ s/^00:50:56:/52:54:00:/;
	  $cmd .= sprintf(' --network bridge=br%d,model=virtio,mac=%s', $ifnum, $hwaddr);
	}
      }
      # Autostart setting.
      if($vmxref->{autostart_val} eq 'poweron') {
	$cmd .= ' --autostart';
      }
      # Now we tell virt-install to create the new VM with all the settings we've
      # constructed.
      &test_cmd($cmd);
      # Now, we've just changed the mac addresses from the VMware range to the
      # KVM range, so make sure the config files on the virtual disk get
      # changed to expect that, or networking won't start.
      if($CFG::TEST_MODE) {
	test_printf 'change hardware addresses in network config files';
      } else {
	my $g = Sys::Guestfs->new();
	$g->add_domain($CFG::IMPORT_NAME);
	$g->launch();
	&guestfs_mount_all($g);
	my($hwaddr);
	try {
	  $g->aug_init('/', 0);
	};
	unless($@ eq '') {
	  croak "Unable to call Sys::Guestfs::aug_init: $@";
	}
	$g->aug_defvar('e0', '/files/etc/sysconfig/network-scripts/ifcfg-eth0');
	try {
	  $hwaddr = $g->aug_get("\$e0/HWADDR");
	};
	unless($@ eq '') {
	    carp "aug_get failed: $@";
	}
	if($hwaddr) {
	  $hwaddr =~ s/^00:50:56/52:54:00/;
	  $g->aug_set('$e0/HWADDR', $hwaddr);
	}
	$g->aug_defvar('e1', '/files/etc/sysconfig/network-scripts/ifcfg-eth1');
	try {
	  $hwaddr = $g->aug_get("\$e1/HWADDR");
	};
	unless($@ eq '') {
	  carp "aug_get failed: $@";
	}
	if($hwaddr) {
	  $hwaddr =~ s/^00:50:56/52:54:00/;
	  $g->aug_set('$e1/HWADDR', $hwaddr);
	}
	$g->aug_save();
	$g->aug_close();
	$g->umount_all();
	$g->shutdown();
	$g->close();
      }
    } else { # VMware -> VMware
      # Just put the directory into $CFG::VM_DIR
      &test_cmd("mv $tempdir/$vmdir $CFG::VM_DIR");
      my $vmxpath = "$CFG::VM_DIR/$vmdir/$vmxfile";
      my $thishost = hostname;
      my($shorthost, $remainder) = split(/\./, $thishost, 2);
      &modify_vmxfile($vmxpath,
		      {
		       'machine.id' => $shorthost,
		       'uuid.action' => 'keep',
		      });
      &register_vm($CFG::IMPORT_NAME);
      &set_owners_perms("$CFG::VM_DIR/$vmdir");
    }
  }
  # And clean up after ourselves.
  &test_cmd("rm -rf $tempdir");
  # Start the VM
  &do_start($CFG::IMPORT_NAME) if($CFG::START);
  autostart_ask $CFG::IMPORT_NAME;
}

sub do_lsvm {
  # List the VMs and whether they're up or down, in a standard format.  The
  # command-line option -c sets $CFG::LSVM_CSS, which causes the output to be
  # in HTML <span> tags, for the 'vmlist' script -- the tags are given class
  # "up" or "down", which the CSS can decide what to do with.

  my(@fields, @vms, %data, %header, %width, %total, %print, %printotal,
     %totalup, %printotalup, %host, %printhost, %percent, %percentup);

  unless($CFG::LSVM_CSS) {
    # Make the list of column fields, which we'll need unless we're in CSS
    # mode.
    @fields = ('vm', 'up');
    push @fields, 'auto' if $CFG::LSVM_AUTO;
    push @fields, 'ss'   if $CFG::LSVM_SS;
    push @fields, ('cpus', 'ram', 'disk_used', 'disk_max') if $CFG::LSVM_RES;
    unless($CFG::LSVM_NOHDR) {
      # Define the column headers, which we'll need unless we're in no-header
      # mode.
      %header =
	(
	 vm        => 'VM',
	 up        => 'Up?',
	 auto      => 'Auto?',
	 ss        => 'SS',
	 cpus      => 'CPUs',
	 ram       => 'RAM',
	 disk_used => 'Disk (Used)',
	 disk_max  => 'Disk (Max)',
	);
    }
  }
  # We will first be populating @vms and %data, then printing output
  # uniformly.
  if($CFG::LSVM_RES) {
    $printotal{vm} = 'TOTAL DEFINED';
    $printotalup{vm} = 'TOTAL ONLINE';
    $printhost{vm} = 'HOST';
    $percent{vm} = 'PERCENT DEFINED';
    $percentup{vm} = 'PERCENT ONLINE';
  }
  if($CFG::KVM) {
    foreach my $dom ($CFG::VMM->list_all_domains()) {
      my $domname = $dom->get_name();
      push(@vms, $domname);
      $data{$domname}->{vm} = $domname;
      $data{$domname}->{up} = ($dom->is_active())?'up':'down';
      if($CFG::LSVM_AUTO) {
	# If the -a option was given, see if each VM was set to autostart.
	$data{$domname}->{auto} = ($dom->get_autostart())?'auto':'noauto';
      }
      if($CFG::LSVM_SS) {
	# If the -s option was given, see how many snapshots the VM has.
	$data{$domname}->{ss} = ($dom->num_of_snapshots());
      }
      if($CFG::LSVM_RES) {
	# If the -r option was given, get info about resources (RAM, CPUs, disk
	# space).
	my $info = $dom->get_info();
	# RAM and CPUs: easy.
	$data{$domname}->{ram} = DataAmount->new($info->{memory}.'kiB');
	$data{$domname}->{cpus} = $info->{nrVirtCpu};
	# Disks: harder. First of all, there are more than one. Second, we have
	# to get their size from the filesystem. Third, they're sparse files,
	# so there's an apparent size and a used size.
	my $t = XML::Twig->new();
	$t->parse($dom->get_xml_description());
	my @disk_elts = $t->get_xpath('./devices/disk[@type="file"]');
	my $max_size = 0;
	my $used_size = 0;
	foreach my $disk_elt (@disk_elts) {
	  my $source_elt = $disk_elt->first_child('source');
	  next unless defined $source_elt;
	  my $f = $source_elt->att('file');
	  debug_printf '%s: disk image listed as %s', $domname, $f;
	  unless(-e $f) {
	    carp (sprintf "VM '%s' reports disk image '%s', which doesn't exist", $domname, $f);
	    next;
	  }
	  my @stat = stat($f);
	  if(defined $stat[7]) {
	    $max_size += $stat[7];
	  } else {
	    carp (sprintf "Unable to determine file size of %s", $f);
	  }
	  my($du) = split /\s+/, `du --block-size=1 $f`;
	  $used_size += $du;
	  debug_printf '%s: %d %s', $f, $stat[7], $du;
	}
	$data{$domname}->{disk_max} = DataAmount->new($max_size.'B');
	$data{$domname}->{disk_used} = DataAmount->new($used_size.'B');

	# Totals
	foreach my $res (qw(ram cpus disk_max disk_used)) {
	  unless($res eq 'cpus') {
	    unless(exists $total{$res}) {
	      $total{$res} = DataAmount->new('0B');
	    }
	    unless(exists $totalup{$res}) {
	      $totalup{$res} = DataAmount->new('0B');
	    }
	  }
	  $total{$res} += $data{$domname}->{$res};
	  if($data{$domname}->{up} eq 'up') {
	    $totalup{$res} += $data{$domname}->{$res};
	  }
	}
      }
    }
  } else {
    my @vmxes = `vmware-cmd -l`;
    chomp(@vmxes);
    foreach my $vmx (@vmxes) {
      my $dir = dirname($vmx);
      my $vm = basename($dir);
      push(@vms, $vm);
      $data{$vm}->{vm} = $vm;
      my $state = `vmware-cmd $vmx getstate | sed -re 's/^.*=[[:space:]]*//'`;
      chomp($state);
      $data{$vm}->{up} = ($state eq 'on')?'up':'down';
      # If the -a option was given, see if each VM was set to autostart.
      # The relevant line in the .vmx file looks like:
      # autostart = "poweron"
      # (or "none")
      if($CFG::LSVM_AUTO) {
	my $autoline = `grep -Ei '^[[:space:]]*autostart[[:space:]]*=' $vmx`;
	my($auto) = ($autoline =~ /^\s*autostart\s*=\s*"?([^"]*)"?/);
	$data{$vm}->{auto} = ($auto eq 'poweron')?'auto':'noauto';
      }
      if($CFG::LSVM_SS) {
	# No support for this yet, but leave a placeholder to avoid unitialized
	# value errors
	$data{$vm}->{ss} = '-';
      }
    }
  }

  if($CFG::LSVM_RES) {
    foreach my $key (@fields) {
      next unless exists $total{$key};
      if($key eq 'ram') {
	$printotal{$key} = $total{$key}->in_min_base2_unit_lvm(1);
      } elsif($key eq 'disk_max' or $key eq 'disk_used') {
	my $unit = $total{$key}->min_base10_unit();
	my $num = int(10*$total{$key}->in($unit) + 0.5)/10;
	$printotal{$key} = "$num $unit"
      } else {
	$printotal{$key} = $total{$key};
      }
    }
    foreach my $key (@fields) {
      next unless exists $totalup{$key};
      if($key eq 'ram') {
	$printotalup{$key} = $totalup{$key}->in_min_base2_unit_lvm(1);
      } elsif($key eq 'disk_max' or $key eq 'disk_used') {
	my $unit = $totalup{$key}->min_base10_unit();
	my $num = int(10*$totalup{$key}->in($unit) + 0.5)/10;
	$printotalup{$key} = "$num $unit"
      } else {
	$printotalup{$key} = $totalup{$key};
      }
    }
    %host =
      (
       vm => 'HOST',
       ram => system_ram,
       cpus => system_cores,
       disk_max => vol_space_total,
       disk_used => vol_space_total,
      );
    foreach my $key (sort(keys(%host))) {
      debug_printf "host{%s}: %s", $key, $host{$key};
    }
    foreach my $key (@fields) {
      next unless exists $host{$key};
      if($key eq 'ram') {
	$printhost{$key} = $host{$key}->in_min_base2_unit_lvm(1);
      } elsif($key eq 'disk_max' or $key eq 'disk_used') {
	my $unit = $host{$key}->min_base10_unit();
	my $num = int(10*$host{$key}->in($unit) + 0.5)/10;
	$printhost{$key} = "$num $unit"
      } else {
	$printhost{$key} = $host{$key};
      }
    }
    foreach my $key (@fields) {
      next unless exists $total{$key} and exists $host{$key};
      next if $key eq 'vm';
      my $percent = undef;
      debug_printf "key: %s total: %s host: %s", $key, ref($total{$key}), ref($host{$key});
      if($key eq 'cpus') {
	$percent = (100*$total{$key})/$host{$key};
      } elsif($key eq 'ram' or $key eq 'disk_max' or $key eq 'disk_used') {
	$percent = (100*$total{$key}->in('B'))/$host{$key}->in('B');
      }
      if(defined $percent) {
	$percent{$key} = sprintf('%3.1f%%', $percent);
      }
    }
    foreach my $key (@fields) {
      next unless exists $totalup{$key} and exists $host{$key};
      next if $key eq 'vm';
      my $percent = undef;
      if($key eq 'cpus') {
	$percent = (100*$totalup{$key})/$host{$key};
      } elsif($key eq 'ram' or $key eq 'disk_max' or $key eq 'disk_used') {
	$percent = (100*$totalup{$key}->in('B'))/$host{$key}->in('B');
      }
      if(defined $percent) {
	$percentup{$key} = sprintf('%3.1f%%', $percent);
      }
    }
  }

  # Format the fields. This way we can base the table column widths on the
  # widths of what's actually going to be printed.
  foreach my $vm (@vms) {
    foreach my $f (@fields) {
      next unless exists $data{$vm}->{$f};
      if($f eq 'ram') {
	$print{$vm}->{$f} = $data{$vm}->{$f}->in_min_base2_unit_lvm(1);
      } elsif($f eq 'disk_max' or $f eq 'disk_used') {
	my $unit = $data{$vm}->{$f}->min_base10_unit();
	my $num = int(10*$data{$vm}->{$f}->in($unit) + 0.5)/10;
	$print{$vm}->{$f} = "$num $unit";
      } else {
	$print{$vm}->{$f} = $data{$vm}->{$f};
      }
    }
  }

  # Output: Unless we're using the CSS output format, first determine the
  # width(s) of the field(s).
  unless($CFG::LSVM_CSS) {
    # First set initial widths to the narrowest each column can be.
    if($CFG::LSVM_NOHDR) {
      %width =
	(
	 vm => 1,
	 up => 2,
	 auto => 4,
	 ss => 1,
	 ram => 2,
	 cpus => 1,
	 disk_max => 4,
	 disk_used => 4,
	);
    } else {
      # If we're printing headers, take them into account when figuring column
      # widths.
      %width = map { $_ => length($header{$_}) } keys(%header);
    }
    # Now see if the data require any of the columns to be widened.
    foreach my $vm (@vms) {
      foreach my $field (@fields) {
	my $w = length $print{$vm}->{$field};
	$width{$field} = $w if $w > $width{$field};
      }
    }
    if($CFG::LSVM_RES) {
      foreach my $field (@fields) {
	my $w;
	if($printotal{$field}) {
	  $w = length $printotal{$field};
	  $width{$field} = $w if $w > $width{$field};
	}
	if($printotalup{$field}) {
	  $w = length $printotalup{$field};
	  $width{$field} = $w if $w > $width{$field};
	}
	if($printhost{$field}) {
	  $w = length $printhost{$field};
	  $width{$field} = $w if $w > $width{$field};
	}
	if($percent{$field}) {
	  $w = length $percent{$field};
	  $width{$field} = $w if $w > $width{$field};
	}
	if($percentup{$field}) {
	  $w = length $percentup{$field};
	  $width{$field} = $w if $w > $width{$field};
	}
      }
    }
  }
  # Output: Print the results, sorted case-insensitively.
  unless($CFG::LSVM_CSS || $CFG::LSVM_NOHDR) {
    # First do the header.
    print join ' ', (map { sprintf "%-$width{$_}s", $header{$_} } @fields), "\n";
    print join ' ', (map { sprintf "%-$width{$_}s", '-'x length($header{$_}) } @fields), "\n";
  }
  foreach my $vm (sort { $a cmp $b } @vms) {
    if($CFG::LSVM_CSS) {
      my $class = $data{$vm}->{up};
      if($CFG::KVM) {
	# Change $class based on other data.
	my $dom = get_domain_by_name $vm;
	if($class eq 'up' and $dom->get_autostart != 1) {
	  $class = 'up_noauto';
	} elsif($class eq 'down' and $dom->get_autostart == 1) {
	  $class = 'down_auto';
	}
      }
      printf("<span class=\"%s\">%s</span>\n",
	     $class, $vm);
    } else {
      print join ' ', (map { sprintf "%-$width{$_}s", $print{$vm}->{$_} } @fields), "\n";
    }
  }
  unless($CFG::LSVM_CSS || $CFG::LSVM_NOHDR) {
    if($CFG::LSVM_RES) {
      print join ' ', (map { sprintf "%-$width{$_}s", '-'x length($header{$_}) } @fields), "\n";
      print join ' ', (map { sprintf "%-$width{$_}s", $printotal{$_} || '' } @fields), "\n";
      print join ' ', (map { sprintf "%-$width{$_}s", $printotalup{$_} || '' } @fields), "\n";
      print join ' ', (map { sprintf "%-$width{$_}s", $printhost{$_} || '' } @fields), "\n";
      print join ' ', (map { sprintf "%-$width{$_}s", $percent{$_} || '' } @fields), "\n";
      print join ' ', (map { sprintf "%-$width{$_}s", $percentup{$_} || '' } @fields), "\n";
    }
  }
}

sub do_merge_all_snapshots() {
  # Merge all of a VM's snapshots.
  my($vmname) = @_;
  $vmname ||= $ARGV[0];
  unless(&vm_name_exists($vmname, 1)) {
    warn "Unable to proceed.";
    if($vmname eq '') {
      &main::HELP_MESSAGE();
    }
    return '';
  }
  # Can't do this to a running VM
  my $restart_after = '';
  if(&vm_running($vmname)) {
    &do_stop($vmname);
    $restart_after = 1;
  }
  print("Merging all of VM ${vmname}'s snapshots ...\n");
  if($CFG::KVM) {
    &merge_kvm_snapshots($vmname);
  } else {
    &merge_vmware_snapshots($vmname);
  }
  print("All snapshots merged.\n");
  &do_start($vmname) if($restart_after);
}

sub do_mkvm {
  # Make a VM.

  unless($ENV{USER} eq 'root') {
    warn "Must be root.";
    return '';
  }

  my $vmname = $ARGV[0];

  # Test the proposed name.
  unless(&vm_name_ok($vmname)) {
    warn "Unable to proceed.";
    if($vmname eq '') {
      &main::HELP_MESSAGE();
    }
    return '';
  }

  # Test the proposed size of the /usr/local disk.
  unless(&have_enough_space()) {
    warn "Unable to proceed.";
    return '';
  }

  # Give the user a chance to say no.
  return '' unless(&ask_to_confirm($vmname));

  # If you can think of any more reasons why we shouldn't go ahead and make the
  # VM, put them before this point

  # Make a landing zone for the VM
  &prepare_vm_home($vmname) || return '';

  # Put the VM there
  unless(&install_stemcell($vmname)) {
    &remove_vm_home($vmname);
    return '';
  }

  # Customize the VM
  unless(&customize_vm($vmname)) {
    &remove_vm_home($vmname);
    return '';
  }

  # Start the VM
  &do_start($vmname) if($CFG::START);

  autostart_ask $vmname;
}

sub do_mvvm {
  # Do the mvvm command, renaming a VM.  The old and new VM names must be the
  # arguments.

  # Check for rootness
  if($ENV{USER} ne 'root') {
    die("Must be root.\n");
  }
  # Get the old and new VM names.
  my ($oldname, $newname) = @ARGV;
  # Make sure old and new names differ
  die("The new name can't be the same as the old name.\n") if($oldname eq $newname);
  # Make sure the old VM exists
  unless(&vm_name_exists($oldname, 1)) {
    warn "Unable to proceed.";
    if($oldname eq '') {
      &main::HELP_MESSAGE();
    }
    exit 1;
  }
  # Test the proposed new name.
  unless(&vm_name_ok($newname)) {
    warn "Unable to proceed.";
    if($newname eq '') {
      &main::HELP_MESSAGE();
    }
    exit 1;
  }
  # Can't rename a running VM
  my $restart_after = '';
  if(&vm_running($oldname)) {
    &do_stop($oldname);
    $restart_after = 1;
  }
  # If you can think of any more reasons why we shouldn't go ahead and rename
  # the VM, put them before this point

  if($CFG::KVM) {
    &rename_kvm_domain($oldname, $newname, $CFG::MVVM_DEEP);
  } else { # VMware case
    &rename_vmware_vm($oldname, $newname);
  }
  printf("VM '%s' renamed to '%s'.\n", $oldname, $newname);
  &do_start($newname) if($restart_after);
  autostart_ask $newname;
}

sub do_rebuild_stemcell {
  # Create a VM, boot it using PXE, and allow Cobbler to generate a stemcell
  # VM.  Then archive that VM for later copying with mkvm.

  unless($ENV{USER} eq 'root') {
    warn "Must be root.";
    return '';
  }

  if($CFG::KVM) {
    unless(&have_x11()) {
      warn "Creating VMs requires X11.  Be sure it is enabled.";
      return '';
    }
  }

  # For any routines we call that refer to this global
  #$CFG::VM_NAME = $CFG::STEMCELL;

  # Make sure a VM with that name doesn't already exist
  if(&vm_name_exists($CFG::STEMCELL, '')) {
    warn "Unable to proceed.";
    return '';
  }

  # Canned settings for stemcell -- these are customized later, when mkvm
  # copies stemcell
  $CFG::USR_LOCAL_SIZE = DataAmount->new('1G');
  $CFG::MEM_SIZE = DataAmount->new('2G');
  $CFG::NUMVCPUS = 1;

  # Make sure we have enough space
  unless(&have_enough_space()) {
    warn "Unable to proceed.";
    return '';
  }

  # If you can think of any more reasons why we shouldn't go ahead and make the
  # VM, put them before this point

  # Prepare a place for the VM
  &prepare_vm_home($CFG::STEMCELL) || return '';

  # Build the VM.
  &build_vm_pxe_anaconda($CFG::STEMCELL) || return '';

  # Tarball the VM to the stemcell archive location.
  my $tarok = &tarball_stemcell();

  # Finally remove the VM because we don't need it anymore.
  if($tarok) {
    &do_rmvm($CFG::STEMCELL, 1);
  }
  return 1;
}

sub do_rebuild_vmware {
  # I find myself doing this all the time too, on VMware hosts anyway --
  # whenever the kernel is updated, VMware Server won't start, because its
  # kernel modules need to be rebuilt.  But of course the vmware-config.pl
  # script that VMware provides also clobbers the contents of
  # /etc/vmware/config and /etc/pam.d/vmware-authd, which we've carefully tuned
  # for our purposes.  So this command preserves those files, runs
  # vmware-config.pl, and restarts VMware Server, all in one command, reducing
  # a laborious process that used to take 5 minutes or more (the more user
  # interaction required, the more pauses there are in the process) to
  # something that takes under 1 minute and only one command.

  # No need for this on KVM
  if($CFG::KVM) {
    die("You don't need to rebuild VMWare Server -- this is a KVM host!\n");
  }
  # Non-root verboten
  if($ENV{USER} ne 'root') {
    die("Must be root.\n");
  }
  # Since vmware won't run unless this is done, if it's running now, it must
  # already have been done, so don't do it again.
  if((system("service vmware status") >> 8) == 0) {
    die("Not reconfiguring vmware server -- it doesn't need it, as it's currently running.\n");
  }
  my $config = '/etc/vmware/config';
  my $authd = '/etc/pam.d/vmware-authd';
  warn "Reconfiguring vmware server ...";
  foreach my $file ($config, $authd) {
    &test_cmd("cp -fp $file $file.bak");
  }
  &test_cmd("/usr/bin/vmware-config.pl -c -d -skipstopstart");
  foreach my $file ($config, $authd) {
    &test_cmd("cp -fp $file.bak $file");
  }
  # Run this fix before starting it back up
  &fix_vmware_perl_api_errors();
  &test_cmd("service vmware start");
}

sub do_rmvm($$) {
  # Remove a VM.  In the case of VMware VMs, this means simply deleting the VM
  # directory and all its contents.  In the case of KVM, this means finding its
  # volumes by examining the XML file and deleting those, and then deleting
  # (undefining) the VM.

  # The second parameter is just whether to skip the y/n confirmation -- if
  # true, it skips the confirmation.  There are some situations where we don't
  # need confirmation, such as removing the temporary stemcell VM after
  # rebuild_stemcell.

  # This subroutine returns true on success, false on failure.

  my $result;

  # Root check
  if($ENV{USER} ne 'root') {
    warn "Must be root.";
    return '';
  }
  # Make sure we have a VM name.  If we are given a VM name in the routine's
  # parameters, use that.  That lets us delete VMs from other routines.
  my($vmname, $skip_confirm) = @_;
  # Otherwise, use the first command-line parameter as the VM name.
  $vmname ||= $ARGV[0];
  unless($vmname) {
    warn "VM name is null.";
    return '';
  }
  # Test the proposed name.
  unless(&vm_name_exists($vmname, 1)) {
    # In the case of VMware, the .vmx file might not exist, but there might
    # still be a directory.  In this pathological case, let's just remove the
    # directory and be done with it.
    unless($CFG::KVM) {
      if(-d "$CFG::VM_DIR/$vmname") {
	warn "$CFG::VM_DIR/$vmname directory exists, but the VM doesn't -- deleting the directory.";
	$result = &test_cmd("rm -rf $CFG::VM_DIR/$vmname");
	return '' unless($result == 0);
	return 1;
      }
    }
    warn "Unable to proceed.";
    if($vmname eq '') {
      &main::HELP_MESSAGE();
    }
    return '';
  }
  # VM running?
  if(&vm_running($vmname)) {
    &do_stop_drastic($vmname);
  }

  # Give the user a chance to say no.
  unless($skip_confirm) {
    return '' unless(&ask_to_confirm($vmname));
  }

  if($CFG::KVM) {
    # If there are snapshots, we have to delete (merge) them.  In KVM, if there
    # are no snapshots, it means that the current state of the VM is the only
    # state.  If there is one snapshot, it means that in addition to the
    # current state, there is a saved previous state.  Deleting that snapshot
    # means merging that saved state with the current state.  More than one
    # snapshot means there are multiple saved previous states, in chronological
    # order; deleting one of them means merging it with the next more recent
    # one.  In any case, the system never becomes inconsistent; there is only
    # the loss of a checkpoint.
    my $dom = $CFG::VMM->get_domain_by_name($vmname);
    # Now, I don't know whether the internal structures will change as I delete
    # snapshots, so I'll get a list of their names, which I know won't change,
    # and delete them by name.
#    my @ssnames = $dom->list_snapshot_names();
#    foreach my $ssname (@ssnames) {
#      printf("Deleting snapshot %s ...\n", $ssname);
#      unless($CFG::TEST_MODE) {
#	$dom->get_snapshot_by_name($ssname)->delete();
#      }
#    }

    # If this is test mode, it's OK for the VM and its XML not to exist -- we
    # might be doing rebuild_stemcell, and we never made the VM to begin with.
    # If it does exist, for example if we're running as rmvm in test mode, read
    # that, but don't do anything.  But otherwise, create some pretend @vol
    # data.  If it's not test mode and the VM doesn't exist, that's pretty
    # weird, as we should have stopped working long before this.
    my @vol = ();
    if($CFG::TEST_MODE) {
      unless($dom) {
	@vol = map {
	  "$CFG::VM_DIR/$CFG::STEMCELL-$_.qcow2"
	} qw(hda hdb);
	debug_printf "(test mode) Using bogus volumes %s", join(', ', @vol);
      }
    }
    unless(@vol) {
      # Parse the XML using XML::Twig to get the virtual disk files
      my $t = XML::Twig->new();
      $t->parse($dom->get_xml_description());
      my @elts = $t->get_xpath('//disk/source[@file]');
      foreach my $elt (@elts) {
	push(@vol, $elt->{att}->{file});
      }
    }
    # Undefine the domain
    print("Undefining $vmname ...\n");
    unless($CFG::TEST_MODE) {
      # Those UNDEFINE_ symbols don't exist in the version of Sys::Virt that
      # comes with RHEL 5, sadly, so we can't be strict here.
      no strict('subs');
      $dom->undefine(Sys::Virt::Domain::UNDEFINE_MANAGED_SAVE | Sys::Virt::Domain::UNDEFINE_SNAPSHOTS_METADATA);
    }
    # Remove the volumes
    foreach my $vol (@vol) {
      printf("Deleting %s ...\n", $vol);
      $result = &test_cmd("rm -f $vol");
      return '' unless($result == 0);
    }
    # Refresh the pool so libvirt knows they're gone
    $CFG::VMM->get_storage_pool_by_name('default')->refresh();
  } else {
    # Tell VMware to drop this VM.  Don't return if this fails; I still want
    # that directory deleted.
    &unregister_vm($vmname);
  }
  &remove_vm_home($vmname) || return '';
  printf("VM '%s' deleted.\n", $vmname);
  autostart_ask $vmname;
  return 1;
}

sub do_swapvm($$) {
  # Swap the first VM for the second.  If $CFG::SWAPVM_DEEP is true, do a
  # "deep" swap, changing the VMs' network identities, not just their names (on
  # KVM).

  my($vm1, $vm2) = @ARGV;

  # Root check
  if($ENV{USER} ne 'root') {
    warn "Must be root.";
    return '';
  }
  # Make sure names are given
  unless($vm1 && $vm2) {
    warn "I need the names of two existing VMs.";
    &main::HELP_MESSAGE();
    exit 1;
  }
  # Make sure the two names differ
  die("Swapping a VM with itself makes no sense.\n") if($vm1 eq $vm2);
  # Make sure both VMs exist
  die("Unable to proceed.\n") unless(&vm_name_exists($vm1, 1) && &vm_name_exists($vm2, 1));
  # Can't rename running VMs
  my $restart_vm1_after = '';
  my $restart_vm2_after = '';
  if(&vm_running($vm1)) {
    &do_stop($vm1);
    $restart_vm2_after = 1;	# because $vm1 will have been renamed to $vm2
  }
  if(&vm_running($vm2)) {
    &do_stop($vm2);
    $restart_vm1_after = 1;	# because $vm2 will have been renamed to $vm1
  }

  # If you can think of any more reasons why we shouldn't proceed, put them
  # before this point

  # We'll be renaming $vm1 to $vm2temp, renaming $vm2 to $vm1, then finally
  # renaming $vm2temp to $vm2.  However, $vm2temp doesn't exist yet -- we need
  # a VM with the same hostname as $vm2, but with a suffix added to its version
  # number to make it unique, or with a version number added if it doesn't
  # already have one.  For example, if $vm1 is "foo.1" and $vm2 is "bar.2",
  # we'll look to see if "bar.2001" exists, move on to "bar.2002" if it does,
  # etc.  Then we'll rename "foo.1" to "bar.2001", rename "bar.2" to "foo.1",
  # then finally rename "bar.2001" to "bar.2".  If $vm2 is "bar" instead, with
  # no version number tacked on, look for "bar.001" instead, and "bar.002" if
  # that exists, etc.  This is based on the convention that a VM's name is
  # equal to the first component of its hostname, plus an optional dot followed
  # by an optional version number.
  my $tempnum = 0;
  my $vm2dot = (index($vm2, '.') == -1)?'.':'';
  my $vm2temp;
  do {
    $vm2temp = sprintf('%s%s%03d', $vm2, $vm2dot, ++$tempnum);
  } while &vm_name_exists($vm2temp, '');
  # Do the renaming
  if($CFG::KVM) {
    &rename_kvm_domain($vm1, $vm2temp, $CFG::SWAPVM_DEEP);
    &rename_kvm_domain($vm2, $vm1, $CFG::SWAPVM_DEEP);
    printf("VM '%s' renamed to '%s'.\n", $vm2, $vm1);
    # This won't need to be a deep rename in any case
    if($CFG::TEST_MODE) {
      print "(test mode) rename $vm2temp to $vm2\n";
    } else {
      &rename_kvm_domain($vm2temp, $vm2, '');
    }
    printf("VM '%s' renamed to '%s'.\n", $vm1, $vm2);
  } else {
    # There is no such thing as a deep rename in the VMware case
    &rename_vmware_vm($vm1, $vm2temp);
    &rename_vmware_vm($vm2, $vm1);
    printf("VM '%s' renamed to '%s'.\n", $vm2, $vm1);
    if($CFG::TEST_MODE) {
      print "(test mode) rename $vm2temp to $vm2\n";
    } else {
      &rename_vmware_vm($vm2temp, $vm2);
    }
    printf("VM '%s' renamed to '%s'.\n", $vm1, $vm2);
  }
  &do_start($vm1) if $restart_vm1_after;
  &do_start($vm2) if $restart_vm2_after;
}

sub do_start {
  # Start up a VM, and wait until it is started

  my($vmname) = @_;
  $vmname ||= $ARGV[0];
  unless(&vm_name_exists($vmname, 1)) {
    warn "Unable to proceed.";
    if($vmname eq '') {
      &main::HELP_MESSAGE();
    }
    return '';
  }
  if(&vm_running($vmname)) {
    warn "VM already running -- unable to proceed";
    return '';
  }
  print("Starting VM $vmname ...\n");
  if($CFG::KVM) {
    if($CFG::TEST_MODE) {
      test_printf 'create %s', $vmname;
    } else {
      # Create it
      $CFG::VMM->get_domain_by_name($vmname)->create();
    }
  } else {
    my $vmxfile = "$CFG::VM_DIR/$vmname/$vmname.vmx";
    &test_cmd("vmware-cmd $vmxfile start");
  }
  unless($CFG::TEST_MODE) {
    # Wait for it to actually be up
    until(&vm_running($vmname)) {
      sleep(5);
    }
  }
  print("VM started.\n");
  return 1;
}

sub do_stop {
  # Shut down a VM in the proper way, and wait for it to be stopped

  my($vmname) = @_;
  $vmname ||= $ARGV[0];
  unless(&vm_name_exists($vmname, 1)) {
    warn "Unable to proceed.";
    if($vmname eq '') {
      &main::HELP_MESSAGE();
    }
    return '';
  }
  unless(&vm_running($vmname)) {
    warn "VM not running -- unable to proceed";
    return '';
  }
  print("Stopping VM $vmname ...\n");
  if($CFG::KVM) {
    if($CFG::TEST_MODE) {
      test_printf 'shutdown %s', $vmname;
    } else {
      $CFG::VMM->get_domain_by_name($vmname)->shutdown();
    }
  } else {
    my $vmxfile = "$CFG::VM_DIR/$vmname/$vmname.vmx";
    &test_cmd("vmware-cmd $vmxfile stop");
  }
  unless($CFG::TEST_MODE) {
    # Wait for it to actually be down
    while(&vm_running($vmname)) {
      sleep(5);
    }
  }
  print("VM stopped.\n");
  return 1;
}

sub do_stop_drastic {
  # Shut down a VM drastically

  my($vmname) = @_;
  $vmname ||= $ARGV[0];
  unless(&vm_name_exists($vmname, 1)) {
    warn "Unable to proceed.";
    if($vmname eq '') {
      &main::HELP_MESSAGE();
    }
    return '';
  }
  unless(&vm_running($vmname)) {
    warn "VM not running -- unable to proceed";
    return ''
  }
  print("Stopping VM $vmname ...\n");
  if($CFG::KVM) {
    if($CFG::TEST_MODE) {
      test_printf 'destroy %s', $vmname;
    } else {
      $CFG::VMM->get_domain_by_name($vmname)->destroy();
    }
  } else {
    my $vmxfile = "$CFG::VM_DIR/$vmname/$vmname.vmx";
    &test_cmd("vmware-cmd $vmxfile stop hard");
  }
  unless($CFG::TEST_MODE) {
    # Wait for it to actually be down
    while(&vm_running($vmname)) {
      sleep(5);
    }
  }
  print("VM stopped with extreme prejudice.\n");
  return 1;
}

###############################################################################
# Main script
###############################################################################

# Do initialization stuff.
&init();

# If called as a command we know, run the appropriate handler subroutine.

if(exists $main::ROUTINES{$CFG::CALLED_AS}) {
  &{$main::ROUTINES{$CFG::CALLED_AS}}();
}

###############################################################################
# Unknown command -- this would be if someone ran vmtool itself sans symlink
###############################################################################

else {
  warn (sprintf "Available commands: %s\n", (join ', ', (sort keys %main::ROUTINES)));
}
