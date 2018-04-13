Summary: OSG Grid Operations Center iptables initscript
Name: gociptables
Version: 1.11
Release: 1
License: GPL
Group: System Environment/Base
URL: http://yum-internal.grid.iu.edu/
Source0: %{name}-%{version}-%{release}.tgz
BuildArch: noarch
Requires: iptables
Requires: iptables-ipv6

%global _binary_filedigest_algorithm 1
%global _source_filedigest_algorithm 1

%description
Replacement for the 'iptables' initscript used by the OSG Grid Operations
Center.  When the 'gociptables' initscript is run with the 'start' parameter,
it executes every file that is set executable in /etc/iptables.d in lexical
order.  This allows for great flexibility in configuring iptables -- these
scripts can be anything (bash, perl, etc.) and presumably use the iptables
commmands to modify the iptables firewall rules to the system administrator's
specifications.  Included are a set of sample iptables scripts.  The
administrator can put other scripts in this directory as required.

The sample scripts show a strategy that has been developed over time at the OSG
GOC, which uses Puppet to synchronize the scripts with 'global' in their names,
making them uniform across all OSG GOC hosts and allowing global changes to be
made quickly and easily (after being tested on a development host).  There is
also a file called 'setup', which contains useful bash functions and variable
settings and is intended to be sourced from the other scripts.  Additionally,
there is an /etc/iptables.d/README file explaining more.

%files
%defattr(0644,root,root,-)
%config /etc/iptables.d/README
%config /etc/iptables.d/setup
%defattr(0744,root,root,-)
%config /etc/iptables.d/00-global-clear
#%config /etc/iptables.d/05-global-packetcounts
%config /etc/iptables.d/10-global-chains
%config /etc/iptables.d/20-global-policies
%config /etc/iptables.d/30-global-rules
%config /etc/iptables.d/90-global-end
/etc/init.d/gociptables

%post
if [ -e /etc/iptables.d/*.rpm* ]; then
  chmod a-x /etc/iptables.d/*.rpm*
fi
service gociptables start
chkconfig --add gociptables

%preun
chkconfig --del gociptables
service gociptables stop

###############################################################################
# Alternate package for RHEL/CentOS 7, with systemd.
###############################################################################

%package -n iptables-services-goc
Summary: Systemd-compatible scripts for GOC ip(6)tables
Requires: /bin/bash
Requires: /bin/sh
Requires: iptables
Requires: systemd

%description -n iptables-services-goc
Files to describe to systemd how to start and stop the firewall using the GOC
/etc/iptables.d/ scripts.

%files -n iptables-services-goc
%defattr(0644,root,root,-)
%config /etc/iptables.d/README
%config /etc/iptables.d/setup
/usr/lib/systemd/system/iptables.service
%defattr(0744,root,root,-)
%config /etc/iptables.d/00-global-clear
#%config /etc/iptables.d/05-global-packetcounts
%config /etc/iptables.d/10-global-chains
%config /etc/iptables.d/20-global-policies
%config /etc/iptables.d/30-global-rules
%config /etc/iptables.d/90-global-end
%defattr(0755,root,root,-)
/usr/libexec/iptables/iptables.init

%post -n iptables-services-goc
if [[ -e /etc/iptables.d/*.rpm* ]]; then
  chmod a-x /etc/iptables.d/*.rpm*
fi
if [[ $1 -eq 1 ]]; then
  # Initial installation
  /usr/bin/systemctl preset iptables.service ip6tables.service >/dev/null 2>&1 || :
fi

%preun -n iptables-services-goc
if [[ $1 -eq 0 ]]; then
  # Package removal, not upgrade
  /usr/bin/systemctl --no-reload disable iptables.service ip6tables.service > /dev/null 2>&1 || :
  /usr/bin/systemctl stop iptables.service ip6tables.service > /dev/null 2>&1 || :
fi

%postun -n iptables-services-goc
/sbin/ldconfig
/usr/bin/systemctl daemon-reload >/dev/null 2>&1 || :
if [[ $1 -ge 1 ]]; then
  # Package upgrade, not uninstall
  /usr/bin/systemctl try-restart iptables.service ip6tables.service >/dev/null 2>&1 || :
fi

###############################################################################
# Common sections
###############################################################################

%prep
%setup -q

%build

%install
rm -rf %{buildroot}
make BUILDROOT="%{buildroot}" install

%clean
rm -rf %{buildroot}

%changelog
* Thu Jan 28 2016 Thomas Lee <thomlee@iu.edu>
- Version 1.11.
- Removed 05-global-packetcounts.  No longer needed.
* Wed Jan 27 2016 Thomas Lee <thomlee@iu.edu>
- Version 1.10.
- Removed everything that calls and references /etc/iptables.d/quickdata, since
  that was a fix for Munin's sake that never really worked; its functionality
  has been moved to /opt/sbin/munin_ip_plugins.py, which is maintained by
  Puppet at present.  It may be put into an RPM one day, but it won't be this
  RPM.
* Thu Jun 25 2015 Thomas Lee <thomlee@iu.edu>
- Version 1.9.
- Added a check at the beginning of the initscript to make sure the running
  kernel's module directories exist.  This should prevent error messages while
  in Anaconda and otherwise using one version of the kernel to install an OS
  that uses another version.
* Thu Jan 29 2015 Thomas Lee <thomlee@iu.edu>
- Version 1.8.
- Added iptables-services-goc subpackage for systemd-based distros.
* Fri Sep 05 2014 Thomas Lee <thomlee@iu.edu>
- Version 1.7, release 6.
- Added a third IP address for the GRNOC.
* Fri Sep 05 2014 Thomas Lee <thomlee@iu.edu>
- Version 1.7, release 5.
- Added a second IP address for the GRNOC.
* Wed Jul 09 2014 Thomas Lee <thomlee@iu.edu>
- Version 1.7.
- Added VLAN 259's IPv6 range, which has now been assigned.
- Reorganized README a bit.
- Added "uiso_ok" and "grnoc_ok" rules to 30-global-rules, which point to empty
  chains, but they can be filled in once there are IPv6 addresses for UISO and
  GRNOC's servers someday.
- Removed 50-local-rules file; it's useless.
* Wed Apr 30 2014 Thomas Lee <thomlee@iu.edu>
- Version 1.6.
- Extended this package to cover ip6tables and IPv6.
* Thu Nov 21 2013 Thomas Lee <thomlee@iu.edu>
- Version 1.5.
- Reject rather than drop packets at the end of the day, in order to be a
  better netizen.
- Removed references to IUPUI network as all machines are now at IUB.
- Test to see whether machine is using old-style or CNDN device names.
* Thu Feb 14 2013 Thomas Lee <thomlee@iu.edu>
- Version 1.4.
- Ensured file permissions agreed with the ones enforced by Puppet.
* Wed Feb 13 2013 Thomas Lee <thomlee@iu.edu>
- Version 1.3.
- Reconciled the differences between the files in this package, the files on
  the Cobbler server that go into stemcell, and the files in the Puppet rules
  that are synchronized to all Puppet clients.
- Reverted 10-global-chains to an earlier version because nothing had changed
  but a comment stating the revision date.
* Fri Nov 16 2012 Thomas Lee <thomlee@iu.edu>
- Version 1.2.
- There was confusion when I used the same lockfile as iptables; the filename
  is now different.
* Fri Nov 16 2012 Thomas Lee <thomlee@iu.edu>
- Version 1.1.
- Changed an infix ! rule to a prefix ! rule (there was a rule like "-d !
  <range>" and I changed it to "! -d <range>"), because infix ! has become
  deprecated in RHEL6, producing a warning message, though it's still accepted.
  The prefix form works in RHEL5/6 without any warning messages.
* Thu Nov 08 2012 Thomas Lee <thomlee@iu.edu>
- Version 1.0.
- Initial build.
