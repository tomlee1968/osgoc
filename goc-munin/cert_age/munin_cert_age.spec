Summary: Munin plugin to monitor certificate age
Name: munin_cert_age
Version: 2.3
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
age of a certificate.  You will probably want to alter
/etc/munin/plugin-conf.d/cert_age so as to list the paths to the certs you want
to monitor.

%files
%attr(0755,root,root) /opt/share/munin/plugins/cert_age
%attr(0777,root,root) /etc/munin/plugins/cert_age
%attr(0644,root,root) %config /etc/munin/plugin-conf.d/cert_age
#%config /etc/munin/plugin-conf.d/cert_age

%prep
%setup -q

%build

%install
make ROOT="$RPM_BUILD_ROOT" install

%clean
rm -rf $RPM_BUILD_ROOT

%changelog
* Mon Jul 09 2012 Thomas Lee <thomlee@iu.edu> -
- Version 2.3.
- Increased warning lead time to 30 days and critical to 14.
* Thu Aug 18 2011 Thomas Lee <thomlee@iu.edu> -
- Version 2.2-2.
- Installed cert_age plugin with mode 0755 instead of 0744.
* Thu Feb 04 2010 Thomas Lee <thomlee@iu.edu> -
- Version 2.2.
- Changed the plugin's Munin category from Other to its own Certificates
  category.
- Changed the BuildArchitecture to 'noarch' in the spec file.
- Changed the Makefile to get its version from the spec file.
* Thu Feb 04 2010 Thomas Lee <thomlee@indiana.edu> -
- Version 2.1.
- Fixed an error in which I inverted the sense of the critical and warning ranges.
* Mon Jan 25 2010 Thomas Lee <thomlee@indiana.edu> -
- Version 2.0.
- Rewrote to actually show certificate age, not days to expiration.  This
  should have the effect of not giving a spurious critical when the value
  returned is 0, which sometimes happens for reasons that I have so far been
  unable to determine.
* Tue Feb 10 2009 Thomas Lee <thomlee@indiana.edu> - 
- Initial build.
