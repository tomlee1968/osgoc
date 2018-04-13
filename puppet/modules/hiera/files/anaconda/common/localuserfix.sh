#!/bin/bash

# localuserfix.sh -- manually go to LDAP and create users and groups
# Thomas Lee <thomlee@iu.edu>
# Last modified 2016-02-02

# This was written for installing CentOS 7 via Cobbler/Anaconda.  Its
# usefulness in other contexts is probably quite limited.

# This solves the issue of being unable to run sssd under systemd-crippled
# Anaconda, such as when installing RHEL/CentOS 7.  Red Hat decided to use
# systemd in RHEL 7 (and CentOS followed suit), drinking so much of the koolaid
# that they incorporated systemd into the install image itself.  However, since
# Anaconda, the Red Hat installation system, runs its postinstall script
# chrooted, systemd is crippled and can't start any services.  (Actually
# systemd has a chroot alternative of its own that might have worked in this
# situation, called systemd-nspawn, but Red Hat didn't use it.)  The issue is
# that we can't start sssd to gain access to the users and groups on the LDAP
# server, and several installation tasks need them: for example, the Puppet
# rules that install everyone's SSH public keys.  To fix this, I wrote this
# script, which just manually queries the LDAP server for the contents of the
# 'goc' user and group and creates temporary user and group accounts for every
# member of that 'goc' group, based on the LDAP records.  The important thing
# is to get the UIDs and GIDs right, so when the system starts for real, files
# meant to be owned by each user end up still owned by that user.

# Usage:
# * To create the temporary local users:
#   $ /path/to/localuserfix.sh on
# * To delete the temporary local users:
#   $ /path/to/localuserfix.sh off

function assure_uid_gid() {
  # Look up the given user/group name and make sure it's available --
  # if it's not in /etc/passwd and /etc/group, use ldapsearch to find
  # the correct uid and gid, and use /sbin/groupadd and /sbin/useradd
  # to add them.  Put a comment in the GECOS field of the /etc/passwd
  # record to indicate that this is temporary and shuld be removed at
  # the end of installation.  This is to compensate for the fact that
  # we can't have sssd running during the postinstall script.

  local id=$1 gid uid members member
  if [[ ! $id ]]; then
    return 1
  fi
  if getent passwd $id >/dev/null || getent group $id >/dev/null; then
    return 2
  fi
  gid=$(ldapsearch -xLLL -H 'ldap:///dc%3Dgoc' -b dc=goc "(&(objectClass=posixGroup)(cn=$id))" gidNumber | grep -i '^gidnumber' | cut -d ' ' -f 2)
  if [[ ! $gid ]]; then
    echo "Unable to find a group named '$id' in LDAP" >/dev/stderr
    return 3
  fi
  if getent group $gid >/dev/null; then
    echo "LDAP gives GID '$gid' for group '$id', but that GID already exists!" >/dev/stderr
    return 4
  fi
  echo "Creating local group '$id' with GID '$gid' ..."
  /sbin/groupadd -g $gid $id
  uid=$(ldapsearch -xLLL -H 'ldap:///dc%3Dgoc' -b dc=goc "(&(objectClass=posixAccount)(uid=$id))" uidNumber | grep -i '^uidnumber' | cut -d ' ' -f 2)
  if [[ ! $uid ]]; then
    echo "Unable to find an account named '$id' in LDAP" >/dev/stderr
    return 3
  fi
  if getent passwd $uid >/dev/null; then
    echo "LDAP gives UID '$uid' for user '$id', but that UID already exists!" >/dev/stderr
    return 4
  fi
  echo "Creating local user '$id' with UID '$uid' ..."
  /sbin/useradd -M -c TEMPORARY -p '!' -g $gid -u $uid $id
  members=($(ldapsearch -xLLL -H 'ldap:///dc%3Dgoc' -b dc=goc "(&(objectClass=posixGroup)(cn=$id))" memberUid | grep -i '^memberuid' | cut -d ' ' -f 2))
  for member in "${members[@]}"; do
    assure_uid_gid $member
    /sbin/groupmems -g $id -a $member
  done
}

function remove_temp_uid_gid() {
  # Remove all records from /etc/passwd and /etc/group whose GECOS
  # field is 'TEMPORARY'.  This should delete all records created by
  # assure_uid_gid and ideally nothing else.
  local users user
  echo -n 'Removing temporary users and groups ...'
  while grep -E '^[^:]+:[^:]+:[^:]+:[^:]+:TEMPORARY:' /etc/passwd >/dev/null; do
    users=($(grep -E '^[^:]+:[^:]+:[^:]+:[^:]+:TEMPORARY:' /etc/passwd | cut -d ':' -f 1))
    for user in "${users[@]}"; do
#      echo "Deleting temporary user/group $user ..."
      /sbin/userdel $user >&/dev/null
      /sbin/groupdel $user >&/dev/null
    done
  done
  echo ' Done.'
}

case "$1" in
    on)
	assure_uid_gid goc
	;;
    off)
	remove_temp_uid_gid
	;;
    *)
	echo "Usage: $0 (on|off)" > /dev/stderr
	exit 1
	;;
esac
exit 0
