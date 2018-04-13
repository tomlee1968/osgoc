#!/bin/bash

# crlsync_check.sh -- make a new CRL RPM if necessary
# Tom Lee <thomlee@iu.edu>
# Begun 2012/07/12
# Last modified 2013/04/08

# OSG Operations tries to be a good netizen by minimizing the number of servers
# that run fetch-crl on all the DOEgrids CAs.  The old way of doing this was to
# run fetch-crl on dubois, make a tarball of all the CRLs, and have all servers
# rsync that tarball, unpacking it into place when it changed.  But there was a
# problem with this: it was done by a cron job that always ran at the same time
# on all servers, so as we added more and more hosts, real and virtual, some of
# the connections were rejected due to simultaneous connection limits.

# To fix this, I tried using Puppet, but not fully -- Puppet merely ran the
# script in cron's place.  Since Puppet runs at a different time on each
# server, there were only a few simultaneous connections on any given minute of
# the hour.  However, although this alleviated the problem, it didn't eliminate
# it, because this method was still not fully scalable.  Because dubois was
# still running other services, and because there were still sometimes multiple
# servers contacting it at the same time, there were still occasional failures
# when too many servers tried to rsync the tarball at the same time.  Much
# better, but still not ideal.

# One might ask, why not use Puppet to distribute the file?  This could work,
# but it would be a kludge similar to how we distribute the SSH public host
# keys -- a cron job running on the Puppet server would insert the CRL tarball
# into the Puppet tree in three different places (in the development, testing,
# and production environments), and Puppet rules would then distribute the file
# only if it had changed and run the script to put the CRLs in place only then.
# The problem with this is the same problem we have with the SSH public host
# keys: we use SVN to control all the other files in the Puppet tree, but then
# there's this file, which comes from somewhere else.  We're rightly moving
# away from distributing the SSH public host keys, and I'm not going to
# introduce another foreign file to distribute just as we're removing an
# earlier one.  No, the solution was to have a fixed set of Puppet files keep a
# constantly-changing set of files updated, much like having Puppet update a
# frequently-changing RPM.  Or perhaps ... exactly like that.

# This script changes the approach completely.  Designed to run on a VM by
# itself, it caches the set of old CRLs, runs fetch-crl to obtain the new CRLs,
# and compares the old and new directories.  If there are any differences, it
# creates an RPM with a timestamp-based version number and sends it to
# yum-internal, our internal YUM repository.  Puppet merely has to have all the
# servers maintain the latest version of this RPM, and this occurs via HTTP,
# which doesn't have the same connection restrictions as rsync/ssh.  Puppet
# still runs at a different time on each server.

###############################################################################
# Settings
###############################################################################

# Path (always set path in scripts that run as root)
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/opt/sbin/:/opt/bin:/usr/local/sbin:/usr/local/bin

# Where to find things
CERTDIR=/etc/grid-security/certificates
NEWCACHE=/opt/var/cache/crlsync/new
OLDCACHE=/opt/var/cache/crlsync/old

# Names of things
RPMNAME=goc-crls
TEMPDIR=""

# Where to send the resulting RPM -- on host yum-internal.grid.iu.edu, there is
# a directory, /opt/var/spool/rpmhopper/new, that is frequently scanned for new
# RPMs to incorporate into the GOC internal RPM repository.  One must log in as
# an authorized user, and there's a special account named 'rpmhopper' that I've
# set up just for this purpose.  The send_crl_rpm function uses these variables
# to send the RPM to the right place via scp.
KEYFILE=id_rsync.dsa
YUMREPO=yum-internal.grid.iu.edu
REPOUSER=rpmhopper
DESTPATH=/opt/var/spool/rpmhopper/new

#DEBUG=1

###############################################################################
# Functions
###############################################################################

function init() {
    # Does setup tasks.
    TEMPDIR=`mktemp -d /tmp/${RPMNAME}-XXXXXXXXXX`
}

function get_latest_ca_certs() {
    # Get the latest OSG CA certs.
    yum -y -q --disablerepo=* --enablerepo=osg update osg-ca-certs
    # Get the latest DigiCertGrid test certs.
    yum -y -q --disablerepo=* --enablerepo=osg-testing update digicert-test-ca-certs
}

function get_latest_crls() {
    # Get the latest CRLs from the OSG CAs.
    if [[ $DEBUG ]]; then
	echo "Running fetch-crl ..."
    fi
    fetch-crl -l $CERTDIR -o $NEWCACHE
}

function test_for_new_crls() {
    # Compares $NEWCACHE with $OLDCACHE.  If there are any
    # differences, return true (0).  If not, return false (1).
    local result=0
    if diff -urq $OLDCACHE $NEWCACHE > /dev/null; then
	# diff returns true if same, false if different
	result=1
    fi
    return $result
}

function make_crl_rpm() {
    # Creates an RPM named $RPMNAME-<timestamp>.rpm of all the CRL
    # files in $NEWCACHE.
    [[ $DEBUG ]] && echo "Making RPM in $TEMPDIR ..."
    local version=`date +%Y%m%d%H%M%S`
    local rpmvers=${RPMNAME}-${version}
    local rpmfile=${rpmvers}-1.noarch.rpm
    # First we need a directory structure to work in.
    local topdir=$TEMPDIR/broot
    mkdir $topdir
    mkdir $topdir/BUILD
    mkdir $topdir/RPMS
    mkdir $topdir/SOURCES
    # Then we need a tarball of the CRLs.
    local tardir=$TEMPDIR/${rpmvers}
    mkdir $tardir
    cp -p $NEWCACHE/*.r0 $tardir
    local tarball=${rpmvers}.tgz
    tar zcf $topdir/SOURCES/$tarball -C $TEMPDIR $rpmvers
    # Then we must generate a spec file.
    local specfile=$TEMPDIR/$RPMNAME.spec
    cat <<EOF > $specfile
Summary: OSG Operations Internal CRL Collection
Name: $RPMNAME
Version: $version
Release: 1
License: GPL
Group: System Environment/Base
URL: http://yum-internal.grid.iu.edu/yum/$RPMNAME-$VERSION-1.rpm
Source0: %{name}-%{version}.tgz
BuildRoot: %{_topdir}/BUILDROOT
BuildArchitectures: noarch

%global _binary_filedigest_algorithm 1
%global _source_filedigest_algorithm 1
%define _binary_filedigest 1
%define _binary_payload w9.gzdio

%description
This RPM contains the latest CRLs from all the CAs whose certificates are in
/etc/grid-security/certificates on crlsync.grid.iu.edu.  Currently this
includes the OSG CA certificates and the DigiCertGrid test certificates.  This
RPM is frequently rebuilt.  Not recommended for servers that run their own
fetch-crl and/or have a divergent collection of CA certificates in
/etc/grid-security/certificates.

%files
%defattr(0644,root,root,-)
EOF
    pushd $NEWCACHE > /dev/null
    for file in *.r0; do
	echo $CERTDIR/$file >> $specfile
    done
    popd > /dev/null
    cat <<EOF >> $specfile

%prep
%setup -q

%install
mkdir -p \$RPM_BUILD_ROOT/$CERTDIR
tar zxf %{_sourcedir}/$tarball -C \$RPM_BUILD_ROOT/$CERTDIR --strip-components 1

%clean
rm -rf \$RPM_BUILD_ROOT
EOF
    # Now build the RPM
    rpmbuild --quiet --define "_topdir $topdir" -bb $specfile
    mv $topdir/RPMS/noarch/$rpmfile $TEMPDIR
}

function send_crl_rpm() {
    # Sends the new RPM to yum-internal for it to pick up and make
    # available to other servers.
    scp -p -q -i $HOME/.ssh/$KEYFILE $TEMPDIR/$RPMNAME-*.rpm $REPOUSER@$YUMREPO:$DESTPATH
}

function cleanup() {
    # Does cleanup tasks, such as erasing the RPM build directory and
    # moving the files in $NEWCACHE to $OLDCACHE.
    rm -f $OLDCACHE/*
    mv $NEWCACHE/* $OLDCACHE
    rm -rf $TEMPDIR
}

###############################################################################
# Main script
###############################################################################

init
get_latest_crls
if test_for_new_crls; then
    make_crl_rpm
    send_crl_rpm
fi
cleanup
