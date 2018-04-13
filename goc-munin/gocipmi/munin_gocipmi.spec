Summary: Munin plugin to monitor sensors with IPMI
Name: munin_gocipmi
Version: 1.0
Release: 2
License: GPL
Group: System Environment/Base
URL: http://internal.grid.iu.edu/
Source0: %{name}-%{version}-%{release}.tgz
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root
BuildArchitectures: noarch
Requires: munin-node
Requires: config(munin-node)
Requires: /usr/bin/ipmitool
Obsoletes: munin_ipmisens2

%global _binary_filedigest_algorithm 1
%global _source_filedigest_algorithm 1

%description
This plugin for the Munin monitoring system lets Munin monitor and graph the
fan speeds, temperatures, and other system health indicators that can be
accessed via IPMI.

%files
%attr(0755,root,root) /opt/share/munin/plugins/gocipmi_
%attr(0755,root,root) /opt/share/munin/plugins/ipmiget
%attr(0777,root,root) /etc/munin/plugins/gocipmi_dell_fan
%attr(0777,root,root) /etc/munin/plugins/gocipmi_dell_temp
%attr(0644,root,root) %config /etc/munin/plugin-conf.d/gocipmi
%config /etc/munin/plugin-conf.d/gocipmi
%attr(0644,root,root) /etc/cron.d/ipmiget

%prep
%setup -q

%build

%install
rm -rf $RPM_BUILD_ROOT
make ROOT="$RPM_BUILD_ROOT" install

%clean
rm -rf $RPM_BUILD_ROOT

%changelog
* Wed Oct 03 2012 Thomas Lee <thomlee@iu.edu> - 
- Renamed to gocipmi; version 1.0.
* Mon Oct 01 2012 Thomas Lee <thomlee@iu.edu> - 
- Version 2.0.
- Rewrote in Perl to deal with data in memory, rather than putting it through a
  series of grep, awk and sed calls, in hopes of running more efficiently on
  busy servers such as glidein.
* Mon Sep 17 2012 Thomas Lee <thomlee@iu.edu> - 
- Version 1.6.
- There is a missing version 1.5 whose source I can't find at present, but I've
  incorporated its changes into this version.
- As RHEL 6 no longer has OpenIPMI-tools as a package, instead packaging the
  ipmitool executable in its own ipmitool package, I've changed this spec file
  to avoid dependency issues by requiring /usr/bin/ipmitool instead.
* Mon Jul 20 2009 Thomas Lee <thomlee@indiana.edu> - 
- Version 1.4.
- Made the mode of /etc/cron.d/ipmiget 0644 instead of 0744.
* Mon Apr 27 2009 Thomas Lee <thomlee@indiana.edu> - 
- Initial build.

