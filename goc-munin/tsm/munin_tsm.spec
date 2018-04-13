Summary: Munin plugin to monitor time since last TSM backup
Name: munin_tsm
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
amount of time elapsed since the last TSM backup.

%files
%attr(0755,root,root) /opt/share/munin/plugins/tsm
%attr(0777,root,root) /etc/munin/plugins/tsm

%prep
%setup -q

%build

%install
make ROOT="$RPM_BUILD_ROOT" install

%clean
rm -rf $RPM_BUILD_ROOT

%changelog
* Thu Aug 18 2011 Thomas Lee <thomlee@indiana.edu> - 
- Initial RPM build.

