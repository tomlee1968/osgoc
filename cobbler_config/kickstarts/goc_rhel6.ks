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
text

## Firewall settings
firewall --enable --ssh --trust=eth1

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

## #if $getVar('stemcell', '')
## Use custom stemcell-only network settings for stemcell building
## network --device=eth0 --onboot=yes --bootproto=static --ip=129.79.53.51 --netmask=255.255.255.0 --gateway=129.79.53.1 --nameserver="192.168.96.4,192.168.97.12,129.79.1.1,129.79.5.100" --hostname=interjection.uits.indiana.edu
## network --device=eth1 --onboot=yes --bootproto=dhcp
## #else
network --device=$getVar('if01', '') --onboot=yes --bootproto=static --ip=129.79.53.51 --netmask=255.255.255.0 --gateway=129.79.53.1 --nameserver="192.168.96.4,192.168.97.12,129.79.1.1,129.79.5.100" --hostname=interjection.uits.indiana.edu
network --device=$getVar('if02', '') --onboot=yes --bootproto=dhcp
## #end if

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
#if $getVar('virtual', '')
services --disabled=anacron,avahi-daemon,avahi-dnsconfd,conman,cups,dnsmasq,firstboot,gpm,haldaemon,ip6tables,ipmi,iptables,iscsi,iscsid,kdump,kudzu,mcstrans,multipathd,netconsole,netfs,netplugd,NetworkManager,nfslock,nscd,ntpdate,pcscd,puppet,radvd,readahead_early,readahead_later,rdisc,restorecond,rhnsd,rhsmcertd,rpcgssd,saslauthd,setroubleshoot,svnserve,winbind,wpa_supplicant,xfs,xinetd,ypbind,yum-updatesd --enabled=acpid,atd,auditd,autofs,crond,irqbalance,lvm2-monitor,messagebus,munin-node,network,nfs,ntpd,oddjobd,portreserve,postfix,psacct,rpcbind,rpcidmapd,rsyslog,sshd,sssd,sysstat,udev-post
#else
services --disabled=anacron,avahi-daemon,avahi-dnsconfd,conman,cups,dnsmasq,firstboot,gpm,haldaemon,ip6tables,iptables,iscsi,iscsid,kdump,kudzu,mcstrans,multipathd,netconsole,netfs,netplugd,NetworkManager,nfslock,nscd,ntpdate,pcscd,puppet,radvd,readahead_early,readahead_later,rdisc,restorecond,rhnsd,rhsmcertd,rpcgssd,saslauthd,setroubleshoot,svnserve,winbind,wpa_supplicant,xfs,xinetd,ypbind,yum-updatesd --enabled=acpid,atd,auditd,autofs,crond,ipmi,irqbalance,lvm2-monitor,messagebus,munin-node,network,nfs,ntpd,oddjobd,portreserve,postfix,psacct,rpcbind,rpcidmapd,rsyslog,sshd,sssd,sysstat,udev-post
#end if

## RHEL installation key: skip
key $getVar('rhel_key', '--skip')

###############################################################################
## The %pre section actually runs first
###############################################################################

%pre
#if $getVar('console_log', '')
exec < /dev/console >& /dev/console
#else
$SNIPPET('log_ks_pre')
#end if
$kickstart_start

# Start networking
#if $getVar('kvmhost', '')
ifconfig $if01 129.79.53.51 netmask 255.255.255.0
route add default gw 129.79.53.1 dev $if01
dhclient $if02
echo "KVM host configuration"
#else if $getVar('stemcell', '')
ifconfig eth0 129.79.53.51 netmask 255.255.255.0
route add default gw 129.79.53.1 dev eth0
echo "Stemcell build configuration"
#else
$SNIPPET('pre_install_network_config')
#end if

##$SNIPPET('goc_install_pause')

## The pre_anamon snippet enables install log monitoring; see /etc/cobbler/settings
$SNIPPET('pre_anamon')

###############################################################################
## Package selection
###############################################################################

## Packages are included by just listing their names, one per line.  You can
## exclude packages that would otherwise be included by prefixing their names
## with '-'.  In at least some distros, packages are organized into groups, and
## you can include a group by referring to it with a '@' prefixed to its name.
## You can explicitly exclude an entire group by prefixing it with a '-' too,
## before the '@'.

## To see a list of packages in a distro (a Red Hat one, anyway), go to the
## distro's home directory, enter the repodata subdirectory, and look for the
## *comps.xml file.

## This XML file describes how Anaconda should treat the package groups, which
## are denoted with <group> tags.  Each group has a <default> tag containing
## either 'true' or 'false', which specifies whether this group is included by
## default when installing the distro.  'true' means that the group will be
## included unless you explicitly say not to ('-@group'), and 'false' means
## that the group won't be included unless you explicitly include it
## ('@group').  You can specify either the <id> or the <name> of the group
## ('@directory-client' and '@Directory Client' are equivalent).

## You'll have to scroll past all the language-specific localization strings to
## get to the <packagelist> section for that group, then read the <packagereq>
## tags.  Each <packagereq> has a 'type' attribute and contains the package
## name.

## There are 3 types of packages: mandatory, default and optional.  Mandatory
## means that if you include this group, you get this package no matter what,
## default means you get it unless you say otherwise ('-package'), and optional
## means you *don't* get it unless you say otherwise ('package').

## Therefore, if you don't specify anything in the %packages section, you will
## get every package marked "type='default'" or "type='mandatory'" from every
## group marked "<default>true</default>", and nothing else.  Anything from
## default groups marked optional, and anything from non-default groups, will
## not be installed.

## There is one special group: 'core'.  Not only is 'core' included by default,
## you have to do something special if you don't want to include it.  It's
## usually really bad for the bootability and functionality of your OS if you
## exclude it, though.  You can include only the 'core' group if you want the
## smallest possible installation, though.  You can, of course, exclude
## individual packages from the 'core' group as long as they're not marked
## 'mandatory'.

%packages
-@Applications
emacs

@Base
-cpuspeed
-dmraid
logwatch
-mdadm
ntp
oddjob
-pcmciautils
psacct
redhat-lsb
-smartmontools
vim-enhanced
-wireless-tools
yum-plugin-downloadonly
yum-presto

-@Client management tools

-@Console internet tools
-fetchmail
ftp
-mutt

@Core
-subscription-manager

-@Debugging tools

-@Desktop
-NetworkManager
-vnc-server

-@Development tools
make
patch
subversion

-@Dial-up Networking Support
-isdn4k-utils
-rp-pppoe

@Directory Client
certmonger
-nscd
-openldap-clients
-pam_ldap
sssd
sssd-tools
sssd-client

-@E-mail server
-dovecot
postfix
-sendmail
-spamassassin

@Emacs
emacs-nox

#unless $getVar('stemcell', '')
@Fonts
dejavu-sans-fonts
#end unless

-@General Purpose Desktop
vim-X11

-@Graphics Creation Tools

-@Hardware Monitoring Utilities
-smartmontools

-@KDE Desktop

-@Large Systems Performance

@Network file system client

-@Network Infrastructure Server

-@Networking Tools
nc

-@Performance Tools

@Perl Support
perl-Date-Calc
perl-Date-Manip
perl-XML-Twig

-@Printing Client

@Server Platform
redhat-lsb

-@server-policy

-@Smart card support
-ccid

-@System Administration Tools
symlinks

-@X Window System
-wdaemon
xorg-x11-apps
xorg-x11-server-utils
xorg-x11-xauth

#unless $getVar('stemcell', '')
# Extra packages
urw-fonts
#end unless

#unless $getVar('virtual', '')
# Packages for physical servers only
OpenIPMI
OpenIPMI-libs
#end unless

# EPEL packages
augeas
augeas-libs
facter
munin-node
puppet
ruby-augeas
ruby-shadow

# Local packages
##cilogon-ca-certs
confsync-dyndns
goc-ca-cert
gociptables
##osg-ca-certs
goc-crls
osupdate
gocloc
munin_puppet
#unless $getVar('virtual', '')
munin_gocipmi
munin_ipc
#end unless
#if $getVar('stemcell', '')
gocvminsta
#end if

###############################################################################
## The %post section runs last
###############################################################################

%post
cd /root
#if $getVar('console_log', '')
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

$SNIPPET('post_install_kernel_options')
$SNIPPET('download_config_files')

## This just sets an environment variable in /etc/profile.d so the
## system is aware of the Cobbler server's IP -- this allows the Koan
## system to work, and although we currently don't use it, this will
## set things up so we can if we decide to.
$SNIPPET('koan_environment')

$SNIPPET('goc_get_stemcellize')
$SNIPPET('goc_install_root_ssh_keys')
## $SNIPPET('goc_install_pause')

#if $getVar('kvmhost', '')
$SNIPPET('goc_interjection_networking')
#else if $getVar('stemcell', '')
$SNIPPET('goc_stemcell_networking')
#else
$SNIPPET('post_install_network_config')
#end if

$SNIPPET('goc_configure_netfiles')

## Can't run oddjobd without messagebus, and apparently Anaconda won't start it
service messagebus start

$SNIPPET('goc_configure_iptables')
$SNIPPET('goc_create_directories')
$SNIPPET('goc_install_install')
$SNIPPET('goc_configure_openldap')

## $SNIPPET('goc_install_pause')

$SNIPPET('goc_configure_sssd')
## Pause to make sure sssd can obtain 'goc' group, which goc_configure_svn
## requires
getent group goc
echo "Result: $?"
$SNIPPET('goc_install_pause')
## SVN requires sssd -- must install files owned by LDAP groups
##$SNIPPET('goc_configure_svn')

##$SNIPPET('goc_install_pause')

#if $getVar('stemcell', '')
$SNIPPET('goc_configure_usr_local')
$SNIPPET('goc_install_stemcell_certs')
#end if

#unless $getVar('virtual', '')
$SNIPPET('goc_install_guardrails')
#end unless

$SNIPPET('goc_configure_rsyslog')
$SNIPPET('goc_configure_inputrc')
##$SNIPPET('goc_configure_bash')

$SNIPPET('goc_configure_postfix')
$SNIPPET('goc_configure_logwatch')
$SNIPPET('goc_osg_repo')
$SNIPPET('goc_internal_yum_repos')
## $SNIPPET('goc_install_pause')
$SNIPPET('goc_configure_openssh')

## $SNIPPET('goc_install_pause')

$SNIPPET('goc_configure_ntpd')
$SNIPPET('goc_munin_node')
## $SNIPPET('goc_configure_nsswitch')
$SNIPPET('goc_configure_sudo')
$SNIPPET('goc_configure_rootmail')
$SNIPPET('goc_configure_logrotate')
$SNIPPET('goc_configure_automount')

#unless $getVar('virtual', '')
$SNIPPET('goc_install_dell_omsa')
#end unless

$SNIPPET('goc_final_enable')
$SNIPPET('goc_final_disable')
$SNIPPET('goc_interjection_puppet')

## $SNIPPET('goc_install_pause')

#if $getVar('virtual', '')
$SNIPPET('goc_install_vm_specific_software')
#end if

#if $getVar('stemcell', '')
# If the script doesn't delete this file, the Ethernet interfaces on
# all new VMs cloned from this image will be eth2 and eth3
rm -f /etc/udev/rules.d/70-persistent-net.rules
#end if

$SNIPPET('goc_install_ignored')
$SNIPPET('goc_cleanup')
$SNIPPET('goc_starter_logfiles')
#if $getVar('kvmhost', '') or $getVar('vmwhost', '')
$SNIPPET('goc_fix_libguestfs')
#end if
chmod 0755 /etc/cron.d

$SNIPPET('goc_install_pause')

$SNIPPET('post_anamon')
chkconfig --level 2345 anamon off
$kickstart_done
