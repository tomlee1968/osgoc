$SNIPPET('goc_preamble')

# Kickstart configuration file RHEL Family Rescue Mode
#
#Text or graphical mode
text
#
#System  language
#
lang en_US.UTF-8
#
##Language modules to install
##
##langsupport --default=en_US.UTF-8 en_US.UTF-8
#
#System keyboard
#
keyboard us
#
##System mouse
##
#mouse none
#
##Retrieve rescue system from NFS
##
## nfs --server=$yournfsserverip  --dir=/directory/that/contains/disc1/CentOS/RPMS/
#
#Retrieve rescue system from http
#
##url --url http://$yourwebserver/directory/that/contains/disc1/CentOS/RPMS/
url --url=http://$http_server/cblr/links/$distro_name
#
#Network information
#
##network --bootproto=dhcp
network --device=$getVar('if01', '') --onboot=yes --bootproto=static --ip=129.79.53.51 --netmask=255.255.255.0 --gateway=129.79.53.1 --nameserver="192.168.96.4,192.168.97.12,129.79.1.1,129.79.5.100" --hostname=interjection.uits.indiana.edu
network --device=$getVar('if02', '') --onboot=yes --bootproto=dhcp

%pre
#if $getVar('console_log', '')
exec < /dev/console >& /dev/console
#else
$SNIPPET('log_ks_pre')
#end if

$SNIPPET('kickstart_start')

# Start networking
###if $getVar('kvmhost', '')
ifconfig $getVar('if01','') 129.79.53.51 netmask 255.255.255.0
route add default gw 129.79.53.1 dev $getVar('if01','')
dhclient $getVar('if02','')
##echo "KVM host configuration"
###else if $getVar('stemcell', '')
##ifconfig $getVar('if01','') 129.79.53.51 netmask 255.255.255.0
##route add default gw 129.79.53.1 dev $getVar('if01','')
##echo "Stemcell build configuration"
###else
##$SNIPPET('pre_install_network_config')
###end if

$SNIPPET('goc_install_pause')

# Enable installation monitoring
$SNIPPET('pre_anamon')
