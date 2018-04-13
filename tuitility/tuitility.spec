Summary: Text-mode utility
Name: tuitility
Version: 1.0
Release: 1
License: GPL
Group: System Environment/Base
URL: http://internal.grid.iu.edu/
Source0: %{name}-%{version}-%{release}.tgz
BuildArch: noarch
Requires: perl
Requires: perl-Curses-UI
Requires: perl-YAML

%global _binary_filedigest_algorithm 1
%global _source_filedigest_algorithm 1

%description
This script uses a Curses UI to enable various system administration tasks. It
uses a plugin system -- each mode in the Mode menu calls up a plugin that
enables a different management system.

%files
%defattr(0755,root,root,-)
/opt/sbin/tuitility
%defattr(0644,root,root,-)
/usr/local/share/perl5/TUItility/Mode/Services.pm

%prep
%setup -q -n %{name}-%{version}

%build

%install
rm -rf %{buildroot}
make BUILDROOT="%{buildroot}" install

%clean
rm -rf %{buildroot}

%post

%changelog
* Wed Oct 19 2016 Thomas Lee <thomlee@indiana.edu>
- Initial build.
