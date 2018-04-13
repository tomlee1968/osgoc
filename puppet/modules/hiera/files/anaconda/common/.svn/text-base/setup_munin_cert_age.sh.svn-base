#!/bin/bash

# setup_munin_cert_age.sh -- set up Munin certificate monitoring
# Tom Lee <thomlee@indiana.edu>
# Last modified 2011/07/08

# This script checks for certificates to monitor.  If there are any, it makes
# sure the Munin cert_age plugin is installed and creates a configuration file
# pointing the Munin cert_age plugin at those certificates.  If there aren't
# any, it makes sure the plugin is not installed and the config file doesn't
# exist.  Then it restarts munin-node to make sure the changes take effect.

# Any install script that installs host/service certificates should then run
# this script so they can be monitored; this allows Munin to issue alerts when
# the certificates' expiration dates draw near.  This script could also
# periodically be run on any host to make sure that Munin monitors whatever
# certificates that host has.

# This script only checks for certificates named *cert.pem within the
# /etc/grid-security directory hierarchy; it will ignore certificates elsewhere
# in the filesystem or with other filenames.  By OSG GOC convention, though,
# certificates are named cert.pem and are located in
# /etc/grid-security/<service>.  (For host certificates, <service>="host".)
# There is at least one exception, however -- VOMS.  Simply because this is how
# the VOMS software from VDT is configured, VOMS has both a host certificate
# called hostcert.pem and an HTTP cert called httpcert.pem.  This is why this
# script searches for '*cert.pem' -- it should locate GOC standard certificates,
# but it should pick up the VOMS certs too.

# This script, however, ignores stemcell certificates.  The GOC maintains a
# host certificate for stemcell.grid.iu.edu; however, no such host actually
# exists.  The certificate only exists for service installation -- the
# "stemcell" is an image of a baseline RHEL system that we then install a
# service on top of, but this requires a host certificate in some cases (such
# as downloading software from VDT).  Technically it is improper for a host to
# use this certificate once the host is no longer a stemcell (that is, once a
# service has been installed on it), because it now has a service-specific
# hostname and thus should have a hostname-specific host certificate.  But it's
# all right for a host to keep using the stemcell cert if all it's used for is
# re-installation.  What's not all right is for the host to use the stemcell
# cert for the service that it runs.  If the service requires a host
# certificate, the host should have a host-specific cert and not use the
# stemcell cert.  The point is that if the stemcell cert expires, no services
# should be directly affected.

# Just speaking practically, it wastes processing time on the Munin server to
# monitor the stemcell certificate on every single host on which it appears.
# How will we know when the stemcell certificate is about to expire?  Because
# it is renewed on the same date as multiple other certificates that we do
# monitor.

###############################################################################
# Settings
###############################################################################

PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:/opt/sbin:/opt/bin

# The Munin config directory
MUNIN_DIR=/etc/munin

# The config directory for Munin plugins
PLUGIN_CONF_DIR=$MUNIN_DIR/plugin-conf.d

# The config file for the cert_age plugin
CERT_AGE_CONF=$PLUGIN_CONF_DIR/cert_age

###############################################################################
# Main
###############################################################################

# See if there are any certificates to monitor.

# The following command should give us a space-separated list of the full paths
# of all certificates that we care about.
ALLCERTS=`find /etc/grid-security -name '*cert.pem' -printf '%p ' | sed -re 's/ +$//'`

# Turn this into a comma-separated list, ignoring stemcell certs.
CERTS=''
for cert in $ALLCERTS; do
  if ! openssl x509 -subject -noout -in $cert | grep -Fq stemcell; then
    if [ -z "$CERTS" ]; then
      CERTS=$cert
    else
      CERTS="$CERTS,$cert"
    fi
  fi
done

# We now have $CERTS, which either contains a comma-separated list of the full
# paths to the certificates to be monitored, or an empty string meaning there
# are no certificates to be monitored.

if [ -n "$CERTS" ]; then	# There are certificates to monitor.

    # Make sure the plugin is installed.
    if ! rpm -q munin_cert_age >& /dev/null; then
	gocloc -s yum -- yum -q -y --disablerepo=* --enablerepo=goc-internal* install munin_cert_age
    fi

    # Write its config file.
    cat <<EOF > $CERT_AGE_CONF
[cert_age]
user root
env.certs $CERTS
EOF

    chown root:root $CERT_AGE_CONF
    chmod 664 $CERT_AGE_CONF
else				# There are no certificates to monitor.

    # Make sure the plugin is not installed.
    if rpm -q munin_cert_age >& /dev/null; then
	gocloc -s yum -- yum -q -y remove munin_cert_age
    fi

    # Delete its config file.
    rm -f $CERT_AGE_CONF
fi

# Now restart munin-node so the new settings get picked up, whatever they are.
service munin-node restart
