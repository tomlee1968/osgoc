Summary: Tool for handling virtual machines
Name: vmtool
Version: 2.8.32
Release: 1
License: GPL
Group: System Environment/Base
URL: http://yum-internal.grid.iu.edu/
Source0: %{name}-%{version}-%{release}.tgz
BuildArch: noarch
Provides: perl(DataAmount)
Requires: perl(Carp)
Requires: perl(Crypt::Random)
Requires: perl(Math::BigInt)
Requires: perl(NetAddr::IP)
Requires: perl(OSSP::uuid::tie)
Requires: perl(Socket)
Requires: perl(Socket::GetAddrInfo)
Requires: perl(Socket6)
Requires: perl(Sys::Guestfs)
Requires: perl(Sys::Virt)
Requires: perl(Try::Tiny)
Requires: perl(XML::Twig)
Requires: openssl
Requires: xorg-x11-xauth
Requires: xorg-x11-server-utils

%global _binary_filedigest_algorithm 1
%global _source_filedigest_algorithm 1

%description
Script with symlinks to perform various functions related
to virtual machines.

%files
%defattr(0644,root,root,-)
%config /opt/etc/vmtool.config
/etc/profile.d/vmtool_completions.sh
/usr/share/perl5/DataAmount.pm
%defattr(0755,root,root,-)
/opt/sbin/vmtool.pl
/etc/rc.d/init.d/gocvmwhosua
%defattr(0777,root,root,-)
/opt/sbin/allvm
/opt/sbin/autovm
/opt/sbin/buildvm
/opt/sbin/cpvm
/opt/sbin/exportvm
/opt/sbin/importvm
/opt/sbin/lsvm
/opt/sbin/merge_all_snapshots
/opt/sbin/mkvm
/opt/sbin/mvvm
/opt/sbin/noautovm
/opt/sbin/rebuild_stemcell
/opt/sbin/rebuild_vmware
/opt/sbin/rmvm
/opt/sbin/swapvm
/opt/sbin/vmup
/opt/sbin/vmdown

%prep
%setup -q

%build

%install
rm -rf %{buildroot}
make ROOT="%{buildroot}" install

%post
chkconfig --add gocvmwhosua

%preun
chkconfig --del gocvmwhosua

%clean
rm -rf %{buildroot}

%changelog
# Future wish list
# - Figure out why the tarball thermometer isn't right when rebuilding
#   stemcells.  (Is it taking into account files that aren't being included?)
# - Become less dependent on global variables.
* Tue Nov 14 2017 Thomas Lee <thomlee@iu.edu>
- Version 2.8.32.
- Fixed a cwd error.
* Mon Oct 23 2017 Thomas Lee <thomlee@iu.edu>
- Version 2.8.31.
- Switched disk used and allocated colums in lsvm.
- Added explanatory text in lsvm -h.
* Fri Oct 20 2017 Thomas Lee <thomlee@iu.edu>
- Version 2.8.30.
- In lsvm, split disk column into allocated and used columns for clarity.
- Attempted to fix exportvm target file handling.
* Wed Jun 14 2017 Thomas Lee <thomlee@iu.edu>
- Version 2.8.29.
- Added guestfs_set_puppet_environment and -e option to specify Puppet
  environment.
* Thu Apr 20 2017 Thomas Lee <thomlee@iu.edu>
- Version 2.8.28.
- Changed from md5 to sha256 and rsa:1024 to rsa:2048 for making the initial
  Puppet certificate request.
* Tue Jan 17 2017 Thomas Lee <thomlee@iu.edu>
- Version 2.8.27.
- Made BASE_VM_SIZE (size of main virtual drive) 64 GiB instead of 32 GiB.
* Wed Dec 21 2016 Thomas Lee <thomlee@iu.edu>
- Version 2.8.26.
- When rebuilding stemcells, give the VM 2GiB of RAM. CentOS 7.3 cannot install
  on only 1GiB.
* Fri Nov 18 2016 Thomas Lee <thomlee@iu.edu>
- Version 2.8.25.
- Added the -1 option to mkvm, which causes the VM to run Puppet on first boot.
- Added more messages during the process of modifying the installed disk images
  when using mkvm.
* Wed Sep 19 2016 Thomas Lee <thomlee@iu.edu>
- Version 2.8.24.
- Added guestfs_setup_sudoers to write the initial /etc/sudoers.d/goc file, so
  even collaborators can sudo immediately after the VM is created (i.e. without
  Puppet having to run first).
* Wed Aug 24 2016 Thomas Lee <thomlee@iu.edu>
- Version 2.8.23.
- Improved error (and "no error") handling for Sys::Guestfs calls.
- Improved error output using Carp module.
* Tue Aug 23 2016 Thomas Lee <thomlee@iu.edu>
- Version 2.8.22.
- No longer errors out when there is no IPv6 address for the host.
- Uses Sys::Hostname to get the VM host\'s hostname.
* Mon Jul 18 2016 Thomas Lee <thomlee@iu.edu>
- Version 2.8.21.
- Will no longer create VMs that do not end with a period and version number.
* Wed Jun 22 2016 Thomas Lee <thomlee@iu.edu>
- Version 2.8.20.
- The -n option to buildvm and mkvm now does nothing (but does not cause an
  error).
- Buildvm and mkvm now set up network parameters, ssh host certificates, and
  Puppet certificates on the new VM (actions which -n used to enable) by
  default. The new option -u prevents these actions.
- Streamlined command-line option handling.
- When the -y option is given, we no longer ask the user which VM of each
  'family' to make autostart; we just pick the highest version number. Not
  ideal, but better than doing nothing or holding up the script forever.
* Thu Feb 11 2016 Thomas Lee <thomlee@iu.edu>
- Version 2.8.19.
- Added the -y option to mkvm and rmvm to skip the "Are you sure?" questions
  (for scripts that call mkvm/rmvm).
- Removed the "aug_match didn't find key" message that occurs when IPADDR is
  not found in the network config files.  This happens sometimes and is nothing
  to worry (or print warning messages) about.  Just add the new value of
  IPADDR.
* Mon Apr 13 2015 Thomas Lee <thomlee@iu.edu>
- Version 2.8.18.
- Made entire script ipv6 compatible.  This meant a complete rewrite of
  construct_hw_address and major changes to lookup_network_params.  The entire
  structure of the IP addresses within the '$net' hashes that
  lookup_network_params returns has changed.  The guestfs_set_net_parameters
  routine now sets ipv6 addresses if they exist.  The read_temp_gocvm_file and
  make_temp_gocvm_file routines now use the new structure, reading and writing
  the suggested ipv6 addresses.
- While I was at it, aug_get_protect and aug_set_protect now wrap all calls to
  Sys::Guestfs Augeas 'aug_get' and 'aug_set' with code that prevents the death
  of the entire script if there is an error, which Sys::Guestfs should prevent
  but does not.
* Thu Mar 19 2015 Thomas Lee <thomlee@iu.edu>
- Version 2.8.17.
- Added the 'autovm' and 'noautovm' commands, for setting a VM to autostart
  when the host boots up, or not, respectively.
- Added a check, when the user has done something that might affect the number
  of VMs in a "family" (group of VMs with the same base name but different
  version numbers) that autostart, to make sure that exactly one VM with the
  same base name is set to autostart.  Asks the user what to do if this is not
  the case (nothing is one of the options).
- Added some more bash completions.
- When lsvm is called with the '-c' option (CSS mode), added new classes,
  'up_noauto' for VMs that are up but not set to autostart, and 'down_auto',
  for VMs that are down but set to autostart.  This will allow the VM inventory
  page to denote these conditions.
* Wed Mar 18 2015 Thomas Lee <thomlee@iu.edu>
- Version 2.8.16.
- Changes specific to CentOS 7.
- Apparently RHEL/CentOS 7 gets its internal sense of its hostname ('hostname'
  command, initial value of $HOSTNAME environment variable) from the file
  /etc/hostname, rather than from the HOSTNAME setting in
  /etc/sysconfig/network as in earlier versions.  Having the -n option set up
  /etc/hostname in that case.
- As we still have not fully transitioned from using Subversion to using Git,
  the call to the read_mkvm_service_config subroutine has to be commented out.
  This much-requested functionality, to have automatic VM parameter settings
  for various services, was actually never used once implemented anyway.  Sigh.
* Fri Mar 06 2015 Thomas Lee <thomlee@iu.edu>
- Version 2.8.15.
- Fixed a bug in 'lsvm -r': when a KVM domain defines a CD-ROM drive, its <source>
  element will not exist.  This was causing undefined values in some cases, but
  now these will just be skipped over.
- 'lsvm -r' now prints host VM resource totals and system maxima, and the
  percent used of each.
* Mon Mar 02 2015 Thomas Lee <thomlee@iu.edu>
- Version 2.8.14.
- Added the -r option to lsvm, listing the resources each VM uses (RAM, number
  of CPUs, amount of disk space).
* Fri Oct 24 2014 Thomas Lee <thomlee@iu.edu>
- Version 2.8.13.
- Added support for CentOS 7.
* Thu Oct 02 2014 Thomas Lee <thomlee@iu.edu>
- Version 2.8.12.
- guestfs_sign_ssh_key no longer assumes that an SSH host key exists; if one
  doesn't exist, it creates one.  It will now no longer error out of the entire
  script if a host key doesn't exist.
- The -3 option now exists on buildvm, rebuild_stemcell, and mkvm, causing
  $CFG::ARCH to change from 'x86_64' to 'x86' so as to be able to build and use
  32-bit RHEL 5 stemcells.  No support for 32-bit stemcells of other distros!
* Mon Jul 21 2014 Thomas Lee <thomlee@iu.edu>
- Version 2.8.11.
- Made rename_kvm_domain better able to recognize a CentOS distro when it sees
  it.
- Fixed error that occurred when /opt/etc/gocvm/mkvm.pl didn't exist in
  importvm.
* Tue Jul 08 2014 Thomas Lee <thomlee@iu.edu>
- Version 2.8.10.
- Added compatibility for CentOS 6.
* Wed Jun 25 2014 Thomas Lee <thomlee@iu.edu>
- Version 2.8.9.
- Unified test mode printing with test_printf.
- Unified that with debug mode printing with debug_printf.
- Tweaked &preserve_old_tarball slightly.
* Tue Apr 29 2014 Thomas Lee <thomlee@iu.edu>
- Version 2.8.8.
- When lsvm is called on VMware, there were uninitialized value errors due to
  the absence of anything to detect snapshots.  There is now at least
  something; it prints a '-' there.
- Apparently there are cases where /opt/etc/gocvm/mkvm.pl doesn't exist on a
  VM, and this caused swapvm to choke.  The script now checks whether it exists
  first, and if it doesn't, it tries to figure out the distro from /etc/issue,
  and if it can't do that, it just sets it to RHEL 6.
- There were a couple of calls to &debug_print when the package was set to TMP
  in read_temp_gocvm_file; these have been changed to &::debug_print.
* Wed Apr 02 2014 Thomas Lee <thomlee@iu.edu>
- Version 2.8.7.
- When guestfs_create_sign_puppet_cert needs to get the UID and GID for the
  'puppet' user and group, first it tries Augeas, then it tries parsing
  /etc/passwd and /etc/group itself, and then it uses the default of 52.  Back
  on March 11, we had a problem where libguestfs's Augeas couldn't see
  /etc/group on one guest, as if it didn't exist, although it did -- and on
  every other guest, it could see it just fine.  The same thing happened when I
  tried doing the same operation in guestfish, so it isn't this script or the
  Perl bindings.  I tried copying /etc/group and /etc/gshadow to a temporary
  guest, and the problem didn't occur, so it isn't something about the format
  or content of /etc/group on that guest.  Anyway, now there's a fallback in
  case that happens again.
- The guestfs_create_sign_puppet_cert routine now uses eval to trap
  Sys::Guestfs errors.  This prevents those errors from causing the entire
  script to die without further comment.
- When doing an exportvm, exclude virtual disk images whose paths begin with
  /net, so we don't attempt to tarball those multi-terabyte external image
  files that are stored on the NAS device anyway.
- Created debug_print and debug_printf subroutines so as to handle debugging
  output more consistently.
- Made do_lsvm more uniform and added a header to the output, which can be
  suppressed with the -n option to the lsvm command.
* Fri Feb 28 2014 Thomas Lee <thomlee@iu.edu>
- Version 2.8.6.
- Bugfix version.
- Much more minor bug -- the -h option caused an error message rather than
  printing help as it should.  This is because the global memory and disk space
  variables were being converted into DataAmount objects after reading the
  command-line options, but the main::HELP_MESSAGE subroutine (which is called
  as soon as the -h option is encountered) refers to them as if they'd already
  been converted.  Do the conversion before getting the command-line options,
  then do it again, since it checks before converting whether the quantities
  are already DataAmounts or not anyway.
* Fri Feb 21 2014 Thomas Lee <thomlee@iu.edu>
- Version 2.8.5.
- Bugfix version.
- Put an additional check in remove_vm_home -- if the argument is blank for any
  reason, it will return without executing.  This way, even if the bug fixed in
  2.8.4 somehow recurs and something calls remove_vm_home without an argument,
  or with a blank string as an argument, disaster will not occur.
- Fixed some other bugs in mkvm in the VMware case.
* Fri Feb 21 2014 Thomas Lee <thomlee@iu.edu>
- Version 2.8.4.
- Emergency bugfix version.
- Fixed a bug in do_rmvm that called remove_vm_home with an undefined argument
  on a VMware host, causing it to DELETE ALL VMS ON THE HOST.  It will now
  never call remove_vm_home with an undefined argument.
* Thu Feb 20 2014 Thomas Lee <thomlee@iu.edu>
- Version 2.8.3.
- Removed a number of subroutines that are no longer useful now that
  DataAmount.pm exists.
- Rewrote the comments having to do with units in light of DataAmount.pm.
- Added swapvm command, which is basically a wrapper for three mvvm commands.
- Changed cpvm, exportvm, mvvm, rmvm, and swapvm so as to shut down running
  VM(s) before operations that require them to be shut down (and, if they were
  up, bring them back up afterwards -- except in the case of rmvm, of course).
- Added function do_stop_drastic, which does a hard shutdown, and changed
  do_rmvm to call this function automatically if the VM is running -- now that
  we have a yes-or-no confirmation on rmvm, it makes sense for this to be
  automatic (and fast).
- Added merge_all_snapshots command, which does exactly what you imagine it
  does.
- Made mkvm slightly more tolerant of VM version numbers that are not strictly
  numeric (i.e. foo.test123).
* Tue Feb 18 2014 Thomas Lee <thomlee@iu.edu>
- Version 2.8.2.
- Split off the code that handles byte units into module DataAmount.pm.
- The 2.8 code that defined domains in mkvm, mvvm and cpvm was still doing so
  even in test mode; this is now fixed, so test mode will again have no lasting
  effect.
- mvvm wasn't preserving autostart; it is now.
- mvvm -c now checks to make sure the actual hostname part of the VM name is
  different -- if the new name differs from the old only in version number, no
  "deep rename" will be done.
- lsvm uses a read-only connection to libvirtd now; this makes it easier for
  monitor.grid to do its VM inventory.
* Tue Feb 11 2014 Thomas Lee <thomlee@iu.edu>
- Version 2.8.1.
- Put a 'no strict('subs')' in rmvm because the UNDEFINE_ symbols aren't found
  in RHEL 5's version of Sys::Virt, which was causing errors on RHEL 5 but not
  RHEL 6.
* Mon Feb 10 2014 Thomas Lee <thomlee@iu.edu>
- Version 2.8.
- Rewrote (almost) all KVM interactions to directly use the libvirt API via
  Sys::Virt rather than going to the shell and using virsh.  The exception is
  for allvm, which is explicitly for applying virsh commands to all domains.
- Rewrote all guestfish commands to directly use the libguestfs API via
  Sys::Guestfs.
- Made mvvm work in the KVM case.  It now has a -c option that goes into the
  guest's filesystem using libguestfs (via Sys::Guestfs) and makes changes to
  its network identity, and all that entails, including the SSH and Puppet
  certificates.  (No, not InCommon or DigiCert certificates; there's no API for
  getting those signed automatically.)
- When the -n option to mkvm is used, the script now sets the VM's network
  identity directly using Sys::Guestfs, so it will never use the stemcell IP.
  As with the mvvm update, this also sets up the SSH and Puppet host
  certificates.  This is only for KVM virtual hosts, as libguestfs isn't
  compatible with VMware volumes.  Obviously, if one wishes to minimize
  downtime of a production VM by keeping the old VM up until one is ready to
  run the install script on the new VM, one should not use the -n option to
  mkvm.
- Added -s option to lsvm to report how many snapshots each VM has.
- Changed /dev/vda to /dev/sda in create_vdisk_img; apparently libguestfs
  always uses /dev/sda now, though in the past it hasn't.
- Moved things a step closer to being ready for other distros besides RHEL if
  we decide to support them someday.  We'd have to obtain an image tarball for
  them somehow, but if we had one, it wouldn't be too hard to change mkvm so
  that it could install it.  The -r option to mkvm is now a 'distro code'
  rather than an RHEL version.  '5' means RHEL 5, '6' means RHEL 6, and
  presumably '7' would mean RHEL 7, etc.  Now, though, we could have any code
  we like, as long as we set up the script for it.  'mkvm -r u137' could
  specify whatever distro 'u137' meant (some version of Ubuntu, perhaps).
- Made rebuild_stemcell not show the console by default, and added the -x
  option to it if you want to see the console.
- Importvm now changes the VM hostname in /opt/etc/gocvm/mkvm.pl to reflect the
  new VM host.  This uses libguestfs and only works on KVM hosts.
- The /opt/etc/gocvm/mkvm.pl file is still called that, but it doesn't refer to
  mkvm specifically within itself anymore, because other actions write it now.
- Removed the old mkvm_classic command, because nobody used it anyway, and its
  only use was to create a VMware VM from a stemcell image that was years old.
- Got rid of the -a, -c, -m, and -s options to rebuild_stemcell -- they weren't
  even used.
- Added new 'cpvm' command, for copying a VM's parameters to create a new VM,
  or even copying the entire contents of a VM's disks.
- Fixed rmvm so it can quickly delete a VM in the KVM case with snapshots.
- Solved a chicken-and-egg problem: mkvm was looking for its config file in SVN
  before checking the command-line options, but the -h and -v options should
  cause the script to exit before doing that.
* Tue Dec 17 2013 Thomas Lee <thomlee@iu.edu>
- Version 2.7.2.
- Fixed the tar creation thermometer so there aren't two %s at the end
  sometimes.
- Fixed lookup_network_params so it still calls construct_mac_address even if
  the hostname isn't found -- the mechanism for constructing a random MAC
  address has been there for ages, but it wasn't being called.
- Got rebuild_stemcell to remove its temporary VM when it was done, as it used
  to.
* Tue Nov 26 2013 Thomas Lee <thomlee@iu.edu>
- Version 2.7.1.
- Made importvm's tab completion search files too, not just command-line
  options.
- Got rid of the "no such file or directory" errors in rebuild_stemcell.
- Stopped it from asking y/n before deleting the VM after rebuild_stemcell.
* Wed Nov 6 2013 Thomas Lee <thomlee@iu.edu>
- Version 2.7.
- Made RHEL6 the default for mkvm, rather than RHEL5.
- Added Y/N confirmation for mkvm/rmvm.
- Added bash completion for mkvm, rmvm, mvvm, vmup, vmdown, exportvm
- On KVM, check for snapshots and delete them before attempting to delete the
  VM.  KVM doesn't let you delete a VM if it still has snapshots.
- Look for service-specific configuration in SVN (command-line options override
  these).
- Added unified tarball creation with estimated completion thermometer.
- Discovered that in KVM, autostart isn't determined by anything in the XML
  file; it's determined by whether there's a symlink in
  /etc/libvirt/qemu/autostart to the XML file.  Setting autostart must be done
  via 'virsh autostart' command and tested via 'virsh dominfo' command.
- Improved some of the messages printed during mkvm and other processes.
* Fri Apr 26 2013 Thomas Lee <thomlee@iu.edu>
- Version 2.6.13.
- Made mkvm a bit smarter about the 'service' string to choose based on the
  hostname: 'vanilla' and 'supportvm' services are now set correctly, as is
  'backup.grid'.
* Thu Mar 21 2013 Thomas Lee <thomlee@iu.edu>
- Version 2.6.12.
- Added a confirmation print in mkvm so you'll know exactly what stemcell image
  you're using.
- Added a '-a' option to lsvm that causes it to show whether or not each VM is
  set to autostart when the host boots up.
- Changed the '-n' option in mkvm and rebuild_stemcell, which governs whether
  the newly-created VM will be set to automatically start when the host boots
  up, to '-a'.  This matches the new lsvm '-a' option.  As it has always been,
  though, the default is to autostart, so this option tells the VM *not* to
  autostart.
- Added a new '-n' option to mkvm that governs whether the new VM should
  attempt to automatically set up its networking settings when it first boots
  up.  The '-i' option, which governs whether the new VM will attempt to run
  the install script, remains intact, and as before still implies '-n', but now
  you can specify that you just want the networking set up if you're going to
  run the install script yourself.
- In addition to hiding information in the MAC address, we will now be putting
  the same information (and more, in some cases) in guestinfo variables in the
  .vmx file (for VMware) or in the /opt/etc/gocvm directory (for KVM).  The
  gocvminsta script (see the gocvminsta directory in SVN) will look for these
  and act accordingly.  gocvminsta is the script that has been reading the
  hidden information in the MAC address of the newly-created VM up to now --
  it's been in use since early 2012, and all that's happening is that it's
  getting smarter (and mkvm is giving it more information to go on).
* Thu Feb 21 2013 Thomas Lee <thomlee@iu.edu>
- Version 2.6.11.
- The -f option introduced in 2.6.10 introduced a bug that wouldn't allow the
  -r option to work -- the stemcell filename wasn't modified by specifying a
  different RHEL version.  Fixed this.
* Mon Feb 18 2013 Thomas Lee <thomlee@iu.edu>
- Version 2.6.10.
- All newly built (and converted from VMware) KVM VMs will now use virtio for
  disk and network.
- Added -f option to rebuild_stemcell to allow test-building of stemcells
  without disturbing the archive.
- Added -f option to mkvm to allow VMs to be built from test stemcells.
* Mon Feb 11 2013 Thomas Lee <thomlee@iu.edu>
- Version 2.6.9.
- Found a bug in importvm: When importing a VMware tarball, a .vmx file can
  have a value and a reference with the same name (checkpoint.vmState = "" and
  checkpoint.vmState.readOnly = "FALSE").  While VMware doesn't mind this, my
  strategy of building a hashref tree in Perl didn't handle this well.  Now
  things are better, if less straightforward.
* Fri Feb 08 2013 Thomas Lee <thomlee@iu.edu>
- Version 2.6.8.
- I didn't know this, but sometimes .vmx files don't have a numvcpus setting,
  relying instead on the VMware default value of 1 for this.  This was causing
  importvm to emit "undefined value" errors when the exported VMware VM was
  missing numvcpus in its .vmx file.  Importvm now gives numvcpus a value of 1
  if it's not present.
- In VMware's .vmx files, the Ethernet addresses of the adapters are in
  "ethernetX:generatedAddress" when they're randomly generated by VMware rather
  than set by something else.  This was causing importvm to emit "undefined
  value" errors because it was only looking in "ethernetX:address".  Importvm
  now searches "generatedAddress" as well.
* Wed Jan 30 2013 Thomas Lee <thomlee@iu.edu>
- Version 2.6.7.
- When exporting from VMware, I had already excluded non-.vmdk files from
  conversion, but tarball_vmware_files was still trying to archive them.
  They're now excluded from that as well.  In fact, they will be disabled in
  the exported .vmx file, so importvm won't try to find them.
- I made changes to the way exportvm decides the path and filename of the
  export tarball.  Previously, if no path was given on the command line,
  exportvm would generate a filename and create the file in the current
  directory, but now it will be created in $CFG::VM_DIR in this case.  If a
  relative filename is given on the command line, exportvm will still create
  the file in the current directory.  If the name of a directory is given on
  the command line, exportvm will generate a filename and create the file in
  that given directory.  But if what is given is an absolute path, exportvm
  will just use that.
- Fixed up some of the math around setting the sizes of created virtual disk
  files.  It no longer rounds up to the next 1G.
- Removed the requirement that an X11 terminal be available in order to use
  mkvm.  It used to be necessary when mkvm was essentially what is now buildvm,
  but it isn't needed now that mkvm has gone back to building from stemcell.
* Wed Jan 16 2013 Thomas Lee <thomlee@iu.edu>
- Version 2.6.6.
- Added debug code to create_vdisk_img that turned out to be unnecessary.
- Fixed a few bugs in build_vm_pxe_anaconda that appeared during an attempted
  stemcell rebuild.
* Wed Jan 16 2013 Thomas Lee <thomlee@iu.edu>
- Version 2.6.5.
- Neglected to set $CFG::VM_NAME in importvm.
* Wed Jan 16 2013 Thomas Lee <thomlee@iu.edu>
- Version 2.6.4.
- Fixed a parenthesization error in the case where someone runs vmtool.pl
  directly, rather than with a symlink.
- Added a lot of error checking.  Mkvm will now refuse to continue if the VM
  directory exists on VMware.  It will also refuse to continue under a number
  of other error conditions.
- If rmvm finds a VM's directory still exists on VMware even if the VM does
  not, it will still delete that directory.
- The exportvm command now returns the VM to its original state (although
  snapshots remain merged); if it converted any VMware disks to monolithic
  format for the export, it will restore the .vmx file to its original state
  and delete the converted disk files, leaving the original disk files
  untouched.  Thus if exportvm is being used to make a backup, the VM can be
  started up after the export and will run (previously there were problems
  because the newly-created converted disk files and the modified .vmx file had
  the wrong permissions).
* Thu Jan 10 2013 Thomas Lee <thomlee@iu.edu>
- Version 2.6.3.
- Added the exportvm and importvm commands.
- Rearranged the lists of commands/symlinks to be in alphabetical order
  everywhere.
- RPM release 2.6.3-2: I had put the wrong date in the script and spec file.
* Tue Dec 11 2012 Thomas Lee <thomlee@iu.edu>
- Version 2.6.2.
- Added the buildvm command, to build a VM from scratch with Cobbler/Anaconda.
  It still needs some work.
- When building a VM or rebuilding stemcell, the script will no longer
  partition or make filesystems on the main HD, which Anaconda is going to
  re-partition and re-format right away anyway.
- Fixed a bug; the requirement of guestfish in the spec file caused vmtool to
  think that VMware servers were KVM servers.  Using a different and I hope
  more accurate means to determine which type of server it is.
- RPM release 2.6.2-2: Removed guestfish dependency; it was bringing in
  unwanted packages.
* Fri Dec 07 2012 Thomas Lee <thomlee@iu.edu>
- Version 2.6.1.
- Fixed a bug: There's a check to make sure that the /usr/local/ disk image
  isn't larger than 950 GB, which is the biggest VMware Server 1.x can support.
  However, the script was configured to impose that limit regardless of the
  type of VM host, even though KVM hosts don't have that restriction.  I am
  currently unable to determine what the upper limit of a qcow2 disk image's
  size might be.
- The RPM .spec file now officially includes some required packages that
  weren't explicitly required before, such as xorg-x11-xauth (without which one
  cannot run X11 applications as root), xorg-x11-server-utils (which includes
  xset, which we use to determine whether X11 is running), and guestfish (which
  is only a requirement on KVM VMs, I suppose, but is very much required on
  them).
- Also there was a major reorganization of the Makefile at this point.
* Thu Oct 25 2012 Thomas Lee <thomlee@iu.edu>
- Version 2.6.
- Can now create partitions and filesystems on VMware and QEMU/KVM disk images
  before the VM is powered on.  There is now no longer any need for that awful
  chkusrlocal script and the rc.sysinit patch that called it, so I've removed
  it from the stemcell images.
* Thu Sep 13 2012 Thomas Lee <thomlee@iu.edu>
- Version 2.5.
- Fixed a bug in deleting the disk files of QEMU/KVM VMs.
* Tue Sep 11 2012 Thomas Lee <thomlee@iu.edu>
- Version 2.4.
- Fixed a bug in 'allvm' on VMware hosts.
* Fri May 25 2012 Thomas Lee <thomlee@iu.edu>
- Version 2.3.
- I am anticipating that the auto-install feature will be unexpected and
  unwanted at first, so I've reversed the behavior of the -i flag to mkvm.  Not
  automatically setting up the network and running the install script will be
  the default; if the user wants these, the -i flag will make it happen.
* Tue May 15 2012 Thomas Lee <thomlee@iu.edu>
- Version 2.2.
- At Soichi's request, reversed behavior of -p switch in mkvm -- VMs will not
  be started by default after creation, and -p means to start them.
* Fri Apr 27 2012 Thomas Lee <thomlee@iu.edu>
- Version 2.1.
- rebuild_stemcell command now works on VMware hosts, creating
  stemcell-vmw.tar.gz.
- mkvm now takes both KVM and VMware image tarballs from cobbler.goc.
- Image tarballs are now named stemcell-<arch>-<vers>-<type>.tgz, where <arch>
  is i386/x86_64, <vers> is 5/6, and <type> is vmw/kvm.
- Added mkvm_classic command that takes the "classic" stemcell image and
  customizes it as before (only works on VMware hosts).
- Added -p option to mkvm (and mkvm_classic) to not power on the new VM
  immediately.
- Added gocvmwhosua (GOC VMware Host OS Update Assist) initscript, to run
  rebuild_vmware at boot time if vmware is present but not running, as it would
  be if there had just been a kernel upgrade
- Added vmup and vmdown commands.
* Thu Apr 19 2012 Thomas Lee <thomlee@iu.edu>
- Version 2.0.
- vmtool rewritten in Perl.
- Much redundant code rewritten reusably.
- Math operations simplified.
- Added rebuild_stemcell command.
- Changed mkvm command such that it customizes the prebuilt image for KVM, just
  as for VMware.
- Config file rewritten into Perl-readable format.
- Certain config variables such as VM_DIR and VM_VG removed from config file,
  as they are deducible from VM host type.
* Tue Mar 27 2012 Thomas Lee <thomlee@iu.edu>
- Version 1.21.
- Added snapshot_all command.
- Changed vm_running function so it works for both KVM and VMware.
* Thu Mar 08 2012 Thomas Lee <thomlee@iu.edu>
- Version 1.20.
- mkvm was checking for X11 in all cases; now checks only for QEMU/KVM/libvirt,
  not VMware
* Wed Nov 16 2011 Thomas Lee <thomlee@iu.edu>
- Version 1.19.
- QEMU/KVM/libvirt disk image files are now given .qcow2 suffix.
- Checks for X11 when creating QEMU/KVM/libvirt VMs.
* Tue Nov 15 2011 Thomas Lee <thomlee@iu.edu>
- Version 1.18.
- Escaped parentheses in sed command in fix_vmware_perl_api_error.
* Tue Oct 11 2011 Thomas Lee <thomlee@iu.edu>
- Version 1.17.
- Consistent output for lsvm, no matter whether on KVM or VMware.
- "lsvm -c" option to output in HTML format with class tag, for vmlist.
- Perl API errors should never appear again for VMware systems.
- Moving toward mvvm for KVM, but not there yet.
* Fri Sep 30 2011 Thomas Lee <thomlee@iu.edu>
- Version 1.16.
- Now detects whether it is on a KVM or VMware system and behaves accordingly,
  at least for mkvm and rmvm.
* Thu Aug 04 2011 Thomas Lee <thomlee@iu.edu>
- Version 1.15.
- Now detects whether it is on a system that uses separate LVs for VMware VMs
  or whether it has a flat /vm volume for all VMs, and acts accordingly.
* Wed Jul 20 2011 Thomas Lee <thomlee@iu.edu>
- Version 1.14.
- I tweaked the rebuild_vmware command based on months of doing updates.  It
  now fixes the "uninitialized value" problem that allvm also fixes (since
  vmware-config.pl reintroduces the problem whenever it runs) and *does* start
  VMware when it's done.  It restores the backups of the config files no matter
  whether they're newer or not.  It still refuses to run if VMware is already
  running (if it's running, it hardly needs a recompile, does it?).
* Tue Nov 16 2010 Thomas Lee <thomlee@indiana.edu>
- Version 1.13.
- New feature: The allvm command -- any command that you can issue to a single
  VM with vmware-cmd, you can issue to them all with allvm.
- New feature: The rebuild_vmware command -- refuses to run if vmware is
  running, makes backups of /etc/vmware/config and /etc/pam.d/vmware-authd,
  recompiles the VMware modules with the current kernel, restores the backups,
  and then doesn't start VMware.
* Fri Nov 05 2010 Thomas Lee <thomlee@indiana.edu>
- Version 1.12.
- New feature: There is now a -c option to set the number of virtual CPUs on
  the new VM.  The only available values are 1 and 2.
* Mon May 17 2010 Thomas Lee <thomlee@indiana.edu>
- Version 1.11.
- New feature: The mkvm portion of vmtool now takes its stemcell image from
  /home/sysinstall/stemcell.tgz on internal.grid.iu.edu, instead of assuming
  that there will be a /vm/stemcell on the VM host in question.  This way,
  there won't be multiple (and possibly divergent) copies of stemcell around,
  and the new VM will always get whatever is considered the latest version.
- On a related note, I also got rid of code that checks for stemcell's
  existence, so you don't need to have a stemcell VM on the VM host to use
  mkvm.
- Attempted bugfix: We had LVM crash on ruckus when someone tried to use rmvm.
  I think this is due to deleting the LV while it's still active.  The rmvm
  section of vmtool now deactivates the LV before deleting it.  I also inserted
  some pauses, which might help too.
* Thu Feb 18 2010 Thomas Lee <thomlee@indiana.edu>
- Version 1.10.
- New feature: The -m option specifies the new VM's memory size.  Its default
  is now in the config file as MEM_SIZE, and if that's not there, it will just
  fall back to whatever stemcell's memory size is (currently 1024 = 1GiB).
* Thu Feb 18 2010 Thomas Lee <thomlee@indiana.edu>
- Version 1.9.
- Fixed a bug: The vm_running function used to look for a file with extension
  .vmem in the VM's directory to determine whether the VM was currently
  running.  I used to think that VMware created this file whenever a VM was
  running and deleted it when the VM was shut down.  Apparently a VM can be
  running without creating such a file, however, so instead I'm going to issue
  the command "vmware-cmd <.vmx file> getstate", which produces the output
  "getstate() = on" or "... = off" and is always accurate.
- Changed a feature: The -a option to mkvm used to set the new VM's
  "set_autostart" parameter to "poweron", meaning that the VM would always be
  powered on whenever VMware started up.  This is as opposed to setting the
  parameter to "none", meaning that the VM would never be turned on
  automatically and would have to be started manually.  However, by request,
  "poweron" is now the default for new VMs created by mkvm.  The -a option now
  does nothing but print a note to this effect.  The new -n option sets the VM
  so as NOT to autostart when VMware starts, if this behavior is desired.
* Fri Nov 13 2009 Thomas Lee <thomlee@indiana.edu>
- Version 1.8.
- Fixed a bug: if you used the -s option to specify a /usr/local
  disk size ending in one or more zeros, the zeros would be stripped
  off due to a misformed regular expression.  "200GiB" was the same
  as "2GiB".  This no longer happens.
* Thu Nov 05 2009 Thomas Lee <thomlee@indiana.edu>
- Version 1.7.
- We have actually been using this one on grandad for a while.
- The -s command-line option now refers to the size of the disk used for
  /usr/local (/dev/hdb).
- The -a command-line option now sets the VM to autostart when VMware does.
- The mkvm command now sets the machine.id variable to the server name.
- vmtool.conf change: VM_SIZE gone, USR_LOCAL_SIZE added
* Fri Sep 04 2009 Thomas Lee <thomlee@indiana.edu>
- Version 1.6.
- My fix in 1.5 only worked when the VM name was more than 16 characters!  My
  bad.  Now it works for shorter names as well.
* Fri Aug 28 2009 Thomas Lee <thomlee@indiana.edu>
- Version 1.5.
- The ext2/3 filesystem label of a VM volume is now decoupled from the VM name
  and path; it's still generated based on the VM name, but it's now guaranteed
  to be 16 characters or less and unique.
* Tue Jul 28 2009 Thomas Lee <thomlee@indiana.edu>
- Version 1.4.
- I left a debug "exit" in the code; got rid of this.
* Tue Jul 28 2009 Thomas Lee <thomlee@indiana.edu>
- Version 1.3.
- Fixed problems with size parameter.
* Tue Jul 28 2009 Thomas Lee <thomlee@indiana.edu>
- Version 1.2.
- Added size parameter.
* Fri Jun 26 2009 Thomas Lee <thomlee@indiana.edu>
- Version 1.1.
- Added vmtool.conf.
* Thu Jun 25 2009 Thomas Lee <thomlee@indiana.edu>
- Version 1.0.
- Initial build.

