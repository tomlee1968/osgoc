## Cobbler kickstart template for installing Red Hat/CentOS family distros

## This isn't an Anaconda kickstart file.  It's a template that
## Cobbler can use to create an Anaconda kickstart file.

## This might be a good time to mention that kickstart files and
## snippets whose filenames begin with "goc_" are GOC-specific;
## otherwise they came with Cobbler.

## Double-# comments won't show up anywhere.  Single-# comments will
## appear in the final kickstart file, but still won't have any
## effect.  But make sure there's a space after the #, or Cheetah (the
## Python library that processes this template to turn it into a final
## kickstart file) will try to interpret it as a directive, and may
## refuse to process the kickstart file at all, resulting in an empty
## kickstart file and thus an unsuccessful installation.

## You might note the proliferation of $getVar('variablename', '')
## macros -- this is a Cheetah macro that gets a variable's value and
## supplies a default value (an empty string in this case) in case
## that variable is unset.  The problem is that Cheetah treats
## undefined variables very differently from variables that are simply
## set to null strings.  Referring to an undefined variable will cause
## Cheetah to immediately halt processing the template with an error.
## The $getVar() macro protects you from that.  You can either use
## $getVar('variablename', '') wherever you would normally just use
## $variablename, or you can #set variablename=value (note that value
## can be $getVar('variablename', '')) at the start of any file in
## which you refer to $variablename.  You must do this in every file,
## unless you do #set global variablename=value, but be careful with
## that, because it will alter whatever global value the variable had,
## no matter what file set it and no matter what value other files may
## expect it to have.

## A explanation of the Cobbler/Anaconda installation process:

## * The machine starts up.  If its BIOS is configured to use PXE on
##   an interface connected to our private VLAN, it will receive PXE
##   boot data from the Cobbler server, including a kernel and an
##   initrd, and it will start to boot.  There may be a user choice
##   involved here, if the interface's MAC address doesn't match any
##   Cobbler system records, but usually system records exist -- in
##   the case of hardware installations the sysadmin has set them up
##   in advance, and in the case of building virtual 'stemcell'
##   images, the 'mkvm' command gives them a MAC address that it knows
##   will trigger a system record.

## * In a basic environment set up by Cobbler, Anaconda runs, using a
##   kickstart file also supplied by Cobbler (and based on a template
##   like this one).  That kickstart file has four sections: the
##   command (settings) section, the %packages section, the %pre
##   (preinstall) section, and the %post (postinstall) section.

## * The %pre section runs first.  This is just a shell script that
##   will be interpreted by 'sh'.  It will be running in the initial
##   network environment (set up by Cobbler) using a very basic system
##   (also provided by Cobbler and probably derived from a distro
##   install image).  It can read and write files and use whatever
##   networking is configured in Cobbler -- there must be some, or it
##   wouldn't have been able to start Anaconda.

## * The command section runs second, setting the values of all the
##   installation parameters.  Anaconda will then begin the
##   installation, setting up the partitions and volumes on the hard
##   drive(s), etc.

## * The %packages section runs after that.  Anaconda will read the
##   distro and any repos configured in order to install whatever
##   packages are listed here, along with whatever packages are marked
##   to be installed by default in the distro (unless you disable them
##   here).  It scans all packages for dependencies and installs
##   anything that the selected packages depend on as well.

## * The %post section runs last.  Again, this is just a shell script,
##   given to 'sh' to interpret.  It runs in the installation network
##   environment, chrooted to /mnt/sysimage, which is where Anaconda
##   has installed all the packages, meaning that the software is very
##   close to what it will be like on the system once it finally
##   reboots.  One problem with this is that the running kernel will
##   be whatever version runs on the installation image, while the
##   kernel modules available will instead be the ones installed;
##   don't do anything that attempts to load kernel modules, because
##   it will fail.  Another problem I've noticed appears in
##   RHEL/CentOS 7, which use systemd, even in their installation
##   images: systemd is unable to start services while chrooted, so
##   you won't be able to rely on any services.

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
#if $getVar('distro', '') == 'c7'
## cmdline
text
## graphical
#else
text
#end if

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

## If this is CentOS 6, try to work around an issue having to do with the updates repo
## #if $getVar('distro', '') == 'c6'

## repo --name=goc-centos-x86_64-updates-6 --baseurl=http://yum-internal-c6.goc/cblr/repo_mirror/centos-x86_64-updates-6 --cost=1
## repo --name=osg-x86_64-6 --baseurl=http://repo1.goc/osg/3.2/el6/release/x86_64 --cost=2
## repo --name=goc-internal-6 --baseurl=http://yum-internal.goc/yum/repo-6 --cost=2
## repo --name=goc-internal --baseurl=http://yum-internal.goc/yum/repo --cost=2
## repo --name=goc-epel-x86_64-6 --baseurl=http://yum-internal-6.goc/cblr/repo_mirror/epel-x86_64-6 --cost=2
## repo --name=goc-centos-x86_64-plus-6 --baseurl=http://yum-internal-c6.goc/cblr/repo_mirror/centos-x86_64-plus-6 --cost=2
## repo --name=goc-centos-x86_64-extras-6 --baseurl=http://yum-internal-c6.goc/cblr/repo_mirror/centos-x86_64-extras-6 --cost=2
## repo --name=goc-centos-x86_64-6 --baseurl=http://yum-internal-c6.goc/cblr/repo_mirror/centos-x86_64-6 --cost=2
## repo --name=source-1 --baseurl=http://$http_server/cobbler/ks_mirror/$distro_name --cost=3

## #else

## Include repos from profile
$yum_repo_stanza

## #end if

## Network settings

## Note: any network settings in the profile and/or system will only
## affect the kickstart file if you reference the variables such as
## $gateway, $hostname, $ip_address_eth0, $subnet_eth0, etc. (of
## course, the default Cobbler snippets such as
## $SNIPPET('network_config') do access these variables).

## There are three stages of networking in a Cobbler/Anaconda install:
## the initial stage (before any kickstart file runs), the
## installation stage (set up by the kickstart file), and the
## installed stage (which Anaconda sets up on the installed system and
## which take effect after the final reboot; i.e. the networking
## settings you want to have on the installed machine from then
## onward).

## No kickstart file can affect the initial stage; only Cobbler
## settings can affect that.  If you use the 'network_config' snippet
## here in the settings section (you must use the
## 'pre_install_network_config' snippet in the %pre section if you
## want this to work), the installation stage will have the same
## settings.  If you want the installation stage's settings to differ
## from the initial stage's, you will have to customize them.

## Putting the 'network_config' snippet in the command section will
## automatically use all such network information during the install
## phase, but only if you put the 'pre_install_network_config' snippet
## in the %pre section.  You can also get by with neither of those
## snippets by manually setting the network configuration here
## yourself.

## The reason why we're putting things here rather than using
## $SNIPPET('network_config') is because the snippet gets things
## wrong.  I'm writing this years after I tried to get that to work,
## but the snippet makes some assumptions about how the network is set
## up that don't work in our case.  I forget whether it works badly
## because there are two interfaces, because we're doing PXE on the
## second interface rather than the first, or because we have to do
## DHCP on the second interface rather than the first, but it's at
## least one of those.

## $SNIPPET('network_config')

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

## RHEL installation key: skip if RHEL, ignore if not
#if $getVar('distro', '') == '5' or $getVar('distro', '') == '6'
key $getVar('rhel_key', '--skip')
#end if

###############################################################################
## The %pre section actually runs first; the previous were just settings
###############################################################################

%pre
#if $getVar('console_log', '')
## Fix wacky terminal mode
#raw
echo $'\e[20h' >/dev/console
#end raw
stty sane -icanon -F /dev/console
exec </dev/console >&/dev/console
#else
$SNIPPET('log_ks_pre')
#end if

#if $getVar('distro', '') == '5'
$kickstart_start
#else
$SNIPPET('kickstart_start')
#end if

## As mentioned above in the settings section, the
## 'pre_install_network_config' snippet creates the file
## /tmp/pre_install_network_config, which contains 'network' lines for
## the settings section.  It gets its data from the variables set in
## the Cobbler distro, profile and system records (which is also how
## Anaconda sets up the network settings that are in effect right now
## as the %pre section is running -- Cobbler told Anaconda what to
## do).  This only works because the %pre section runs first -- the
## 'network_config' snippet, meant to be used in the settings section,
## includes that /tmp file.
## $SNIPPET('pre_install_network_config')
$SNIPPET('goc_pinc')

## The pre_anamon snippet enables install log monitoring; see
## /etc/cobbler/settings.  Anamon sends log messages generated during
## installation to the Cobbler server, where they are visible in
## /var/log/cobbler/anamon/<systemname> (where <systemname> is the
## name of the Cobbler system record in effect).
$SNIPPET('pre_anamon')

## $SNIPPET('goc_install_pause')

#if $getVar('distro', '') == 'c7'
%end
#end if

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

## If you want the installed network environment to be the same as the
## initial and installer network environments, go ahead and use the
## built-in $SNIPPET('post_install_network_config') here.  Usually
## that's not what we want -- the initial and installer environments
## use interjection.uits.indiana.edu's IP addresses on $if01 and DHCP
## on $if02, whereas there are two situations we want for the
## installed environment:
##
## * If we're rebuilding a virtual 'stemcell' image, we want $if01 to
##   be changed to stemcell.grid.iu.edu's IP addresses.  But $if02
##   should still use DHCP.
##
## * If we're installing some other system, it will probably be a
##   specific one, such as one of the KVM hosts, so it should use the
##   host's proper static IP addresses for both interfaces.  But
##   that's assuming the Cobbler system knows what host it is.  Also,
##   the KVM hosts require special bridging to be set up -- although
##   there are install scripts that take care of that.  So it's best
##   to just get things online for now.
##
## If we really don't know what host it is, it's probably best to
## leave it alone.
#unless $getVar('stemcell', '')
  #if $getVar('kvmhost', '')
    $SNIPPET('goc_interjection_networking')
  #else
    $SNIPPET('post_install_network_config')
  #end if

## There's sometimes an issue when installing on bare metal servers where it
## uses the wrong netmask for IPv6 for the private VLAN. Find the private
## VLAN's adapter and make sure the IPv6 netmask is 48, not 64. Otherwise it
## breaks everything that requires access to the private VLAN from this point
## on. I suspect this comes from unwarranted assumptions made in the default
## Cobbler 'post_install_network_config' snippet.
##
  sed -i -re 's!^[[:space:]]*IPV6ADDR=([fF][cCdD][0-9a-fA-F:]+)/64[[:space:]]*\$!IPV6ADDR=\\1/48!' /etc/sysconfig/network-scripts/ifcfg-$if02
  ifdown $if02
  ifup $if02
  echo "Make sure that interface $if02 has /48 netmask:"
  ip addr show $if02

$SNIPPET('goc_install_pause')

#end unless

## Since Anaconda somehow doesn't work when the centos6 profile
## includes the update repos, install the updates now.
##
#if $getVar('distro', '') == 'c6'
/opt/sbin/osupdate
#end if

## Workaround for Anaconda bug: Anaconda tries very hard to install the
## postfix-incompatible 'ssmtp', no matter how many times I specify '-ssmtp' in
## the packages list. The problem is that 'ssmtp' replaces and overwrites
## several of postfix's binaries with ones that don't work. Fix this craziness
## by removing ssmtp, then removing and reinstalling postfix (because postfix's
## original binaries are now gone, thanks to ssmtp). Puppet can't do this
## because it can't force package removals.
#raw
if rpm -q ssmtp >&/dev/null; then
  rpm -e --nodeps ssmtp
  rpm -e --nodeps postfix
  yum -y -q install postfix
fi
#end raw

rm -f /etc/sssd/sssd.conf
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

#if $getVar('distro', '') == 'c7'
%end
#end if
