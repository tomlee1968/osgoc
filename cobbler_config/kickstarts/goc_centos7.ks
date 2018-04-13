## Cobbler kickstart template for installing CentOS 7

## This isn't an Anaconda kickstart file.  It's a template that
## Cobbler can use to create an Anaconda kickstart file.

## This might be a good time to mention that kickstart files and
## snippets whose filenames begin with "goc_" are GOC-specific;
## otherwise they came with Cobbler.

## Double-# comments won't show up anywhere.  Single-# comments will
## appear in the final kickstart file, but still won't have any
## effect.  But make sure there's a space after the #, or Cheetah (the
## Python library that processes this template to turn it into a final
## kickstart file) will try to interpret it as a directive.

$SNIPPET('goc_preamble')

###############################################################################
## Command section
###############################################################################

## Note: I've used the (R) symbol in a comment to indicate that this parameter
## is required -- TJL 2011/09/26

## (R) System authorization -- uses same options as authconfig command
auth --useshadow --enablemd5 --enablesssd --enablesssdauth --disableldap --disableldapauth --ldapserver ldap://192.168.96.4/,ldap://192.168.97.12/ --ldapbasedn dc=goc --enablemkhomedir

## (R) Bootloader options
bootloader --append="selinux=0" --location=mbr

## Whether to clear any partitions before making new ones
clearpart --all --initlabel

## Text or graphical setup?
##text
cmdline

## Firewall settings
firewall --enable --ssh --trust=$getVar('if02', '')

## Whether to run firstboot utility
firstboot --disable

## (R) Keyboard setting
keyboard us

## (R) Language setting
lang en_US

## (R) Set URL to install from
url --url=http://$http_server/cblr/links/$distro_name

## Include repos from profile
$yum_repo_stanza

## Network settings

## Note: any network settings in the profile and/or system will only
## affect the kickstart file if you reference the variables such as
## $gateway, $hostname, $ip_address_eth0, $subnet_eth0, etc.

## Putting the 'network_config' snippet in the command section will
## automatically use all such network information during the install
## phase, but only if you put the 'pre_install_network_config' snippet
## in the %pre section.  You can also get by with neither of those
## snippets by putting it here yourself.

## Putting the 'post_install_network_config' snippet in the %post
## section will automatically configure the final installed OS with
## all such network information.  The 'pre_install_network_config'
## snippet is not required for this.

## The reason why we're putting things here rather than using
## $SNIPPET('network_config') is because the snippet gets things
## wrong.  I'm writing this years after I tried to get that to work,
## but the snippet makes some assumptions about how the network is set
## up that don't work in our case.  I forget whether it works badly
## because there are two interfaces, because we're doing PXE on the
## second interface rather than the first, or because we have to do
## DHCP on the second interface rather than the first, but it's at
## least one of those.

## network --device=$getVar('if01', '') --onboot=yes --bootproto=static --ip=129.79.53.51 --netmask=255.255.255.0 --gateway=129.79.53.1 --nameserver="192.168.96.4,192.168.97.12,129.79.1.1,129.79.5.100" --hostname=interjection.uits.indiana.edu
## network --device=$getVar('if02', '') --onboot=yes --bootproto=dhcp

$SNIPPET('goc_network_config')

## Reboot, halt, or poweroff when finished?
#if $getVar('stemcell', '')
poweroff
#else
reboot
#end if

## (R) Set root password
rootpw --iscrypted $default_password_crypted

## SELinux setting
selinux --disabled

## Skip X configuration?
skipx

## (R) Time zone setting
timezone Etc/UTC

## Install or upgrade?
install

## Zero out any invalid MBRs
zerombr

$SNIPPET("goc_define_volumes")

## Services to enable/disable
$SNIPPET('goc_services')

## RHEL installation key: skip
##key $getVar('rhel_key', '--skip')

###############################################################################
## The %pre section actually runs first; the previous were just settings
###############################################################################

%pre
#if $getVar('console_log', '')
## Fix wacky terminal mode
stty sane -icanon -F /dev/console
exec < /dev/console >& /dev/console
#else
$SNIPPET('log_ks_pre')
#end if
$SNIPPET('kickstart_start')

# Start networking
## #if $getVar('kvmhost', '')
## ifconfig $getVar('if01','') 129.79.53.51 netmask 255.255.255.0
## route add default gw 129.79.53.1 dev $getVar('if01','')
## dhclient $getVar('if02','')
## echo "KVM host configuration"
## #else if $getVar('stemcell', '')
## ifconfig $getVar('if01','') 129.79.53.51 netmask 255.255.255.0
## route add default gw 129.79.53.1 dev $getVar('if01','')
## echo "Stemcell build configuration"
## #else
## $SNIPPET('pre_install_network_config')
## #end if

$SNIPPET('goc_pinc')

##$SNIPPET('goc_install_pause')

## The pre_anamon snippet enables install log monitoring; see
## /etc/cobbler/settings.  Anamon sends log messages generated during
## installation to the Cobbler server, where they are visible in
## /var/log/cobbler/anamon/<systemname> (where <systemname> is the
## name of the Cobbler system record in effect).
$SNIPPET('pre_anamon')

%end

###############################################################################
## Package selection
###############################################################################

$SNIPPET("goc_packages")

###############################################################################
## The %post section runs last
###############################################################################

%post
$SNIPPET('goc_functions')

cd /root
## Whether to log to console or file
#if $getVar('console_log', '')
  ## Fix wacky terminal mode
  stty sane -icanon -F /dev/console
  exec < /dev/console >& /dev/console
#else
  $SNIPPET('log_ks_post')
#end if

## This is responsible for /etc/yum.repos.d/cobbler-config.repo, which
## should not remain around after installation (see the 'goc_cleanup'
## snippet, which deletes it).  But during installation, it makes sure
## that all the repos available during Anaconda's run are also
## available to this postinstall script.
$yum_config_stanza

##echo "Pausing to check /etc/yum.repos.d/cobbler-config.repo"
##$SNIPPET('goc_install_pause')

## If there are any postinstall kernel options configured in the
## Cobbler distro/profile/system record we're using, this will put
## them in place.
$SNIPPET('post_install_kernel_options')

## If there are any Cobbler-managed configuration file templates
## configured in the Cobbler profile or system record we're using, the
## 'download_config_files' snippet will get them from the server.
## Yes, I know it isn't called 'download_template_files'; I didn't
## name it.  Configure them with the command-line like this:
##
## cobbler system edit --name=<system_name> \
##   --template-files='src1=path1 src2=path2 ...'
##
## where src1/src2/etc. are paths to the source file on the Cobbler
## server and path1/path2/etc. are the paths where the file should be
## placed on the installed system.  (Use 'cobbler profile edit' to
## configure template files associated with a profile record.)  You
## can also use the web UI; edit the profile or system record, go to
## the "Management" tab, and put source=path pairs in the "Template
## Files" box, one per line.  Caveat: You cannot do this with a config
## file that has any underscore characters in its final path, as
## Cobbler replaces / characters with underscores at one point and
## then replaces those underscores with / again at another point.
## Poor planning on their part.  If you need underscores, I suggest
## giving the file an underscore-free temporary name and then using a
## command later in the postinstall script to rename it to its final
## name.
##
## Cobbler processes each file with Cheetah just as it does this
## kickstart file, so if it has anything that looks like a Cheetah
## variable ($example) or control statement (#example at beginning of
## line), you should probably surround it with #raw ... #end raw
## statements.  Also, don't even try to install a binary file this
## way; Cheetah will completely munge it.
$SNIPPET('download_config_files')

## This just drops files into /etc/profile.d called cobbler.sh and
## cobbler.csh, each of which sets an environment variable (for bash
## and csh, respectively) called COBBLER_SERVER to the Cobbler
## server's IP -- this allows the Koan system to work, and although we
## currently don't use it, this will set things up so we can if we
## decide to.
$SNIPPET('koan_environment')

## This obtains the "stemcellize.tgz" tarball, which contains various
## files necessary for converting a newly-created VM into a stemcell
## image.  Many of them are also useful for installing other types of
## GOC-compatible system besides stemcell images.  These are being
## phased out in favor of Anaconda-only Puppet, but some files (such
## as the interjection.uits.indiana.edu Puppet keys and puppet.conf)
## will always be necessary. -- TJL 2016-02-04
##$SNIPPET('goc_get_stemcellize')

## Networking is tricky -- first of all, this isn't going to affect
## the network settings of the system that's running at the time this
## code is being executed, which is a minimal system running Anaconda.
## This affects the network config files on the system being
## installed.  Second of all, what we need depends on what's being
## installed.
##
## If it's a stemcell, if01 needs to have the stemcell.grid.iu.edu IP
## addresses, and if02 needs to be configured to get a private VLAN
## address from the DHCP server.  This is because of the old way we
## used to use to install services, which we sometimes still use: we
## make a new VM, boot it, ssh to it, and then download install
## scripts that change its network parameters to their final values.
## But the new way to do things (with mkvm -n) can change the network
## parameters after unpacking the stemcell but before ever booting the
## VM, so the network config generated here will never actually be
## used in that case.  Puppet now takes care of the stemcell case.
##
## If it's going to be a KVM virtualization host, its initial setup
## configures if01 and if02 as member interfaces of two separate
## network bridges, br0 and br1, which are in turn given the
## interjection.uits.indiana.edu IP address and a DHCP configuration,
## respectively.  We would then login to the VM's console and download
## and run the installation scripts that would set the network
## parameters to the correct values.  We could, however, make the
## Cobbler (or Anaconda-only Puppet) rules aware of the machine's
## hardware addresses so they could determine its IP addresses and set
## them accordingly here.  That would require more work, as well as
## upkeep when more hosts were added.
##
## If it's something else, we fall back on the standard Cobbler
## networking configuration, which allows us to define network
## parameters in the profile and system records.  Unfortunately these
## don't work well with more than one interface, and what's more, if
## we want different network parameters for the installer system
## vs. the installed system, Cobbler isn't able to do that
## automatically.
##
## What kind of networking to configure
#if $getVar('kvmhost', '')
  $SNIPPET('goc_interjection_networking')
#else if $getVar('stemcell', '')
## Moved to Anaconda-only Puppet -- TJL 2016-02-04
##  $SNIPPET('goc_stemcell_networking')
## (but there has to be something here or Cobbler won't build the file)
  echo -n
#else
  $SNIPPET('post_install_network_config')
#end if

## Puppet handles most setup tasks.
$SNIPPET('goc_interjection_puppet')

## Minimize the amount of unnecessary data that gets exported with the
## stemcell image, if that's what we're doing, or at the very least
## leave the system as pristine as possible for whatever's happening
## to it next.
$SNIPPET('goc_cleanup')

## The post_anamon snippet causes your installed system to send its
## /var/log/messages and /var/log/boot.log to the Cobbler server after
## it boots.  I recommend against this, as it adds a SYSV INIT script
## (incompatible with RHEL/CentOS 7 and beyond, as they use systemd)
## that will run at next boot and may run with every boot, sending
## superfluous log messages to the Cobbler server.  Besides, if you've
## already used pre_anamon, the Cobbler server already has the
## installer log messages.
##$SNIPPET('post_anamon')

echo "Pausing for final check."
$SNIPPET('goc_install_pause')

$SNIPPET('kickstart_done')

%end
