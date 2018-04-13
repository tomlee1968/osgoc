Summary: Munin plugin to monitor Puppet updates
Name: munin_puppet
Version: 1.0
Release: 1
License: GPL
Group: System Environment/Base
URL: http://internal.grid.iu.edu/
Source0: %{name}-%{version}.tgz
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root
BuildArchitectures: noarch
Requires: munin-node
Requires: config(munin-node)
Requires: perl-TimeDate

%global _binary_filedigest_algorithm 1
%global _source_filedigest_algorithm 1

%description
This plugin for the Munin monitoring system lets Munin monitor and graph the
time since the Puppet agent last ran to update the system.

%files
%attr(0755,root,root) /opt/share/munin/plugins/puppet
%attr(0777,root,root) /etc/munin/plugins/puppet

%prep
%setup -q

%build

%install
make ROOT="$RPM_BUILD_ROOT" install

%clean
rm -rf $RPM_BUILD_ROOT

%changelog
* Wed Mar 14 2012 Thomas Lee <thomlee@iu.edu> - 
- Initial RPM build.

