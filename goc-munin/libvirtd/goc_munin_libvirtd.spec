Summary: Munin plugin to monitor libvirtd VM statistics
Name: goc_munin_libvirtd
Version: 1.1
Release: 1
License: GPL
Group: System Environment/Base
URL: http://yum-internal.grid.iu.edu/
Source0: %{name}-%{version}-%{release}.tgz
#BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root
BuildArch: noarch
Requires: munin-node
Requires: config(munin-node)
Requires: perl(DataAmount)
Requires: perl(Proc::ProcessTable)
Requires: perl(Sys::Virt)
Requires: perl(XML::Twig)

%global _binary_filedigest_algorithm 1
%global _source_filedigest_algorithm 1

%description
This plugin for the Munin monitoring system lets Munin monitor and graph
statistics for virtual machines on a typical KVM/qemu/libvirtd host at OSG
Operations.

%files
%defattr(0755,root,root,-)
/opt/share/munin/plugins/libvirtd_cpus
/opt/share/munin/plugins/libvirtd_disk_apparent
/opt/share/munin/plugins/libvirtd_disk_apparent_all
/opt/share/munin/plugins/libvirtd_disk_real
/opt/share/munin/plugins/libvirtd_disk_real_all
/opt/share/munin/plugins/libvirtd_ram_defined
/opt/share/munin/plugins/libvirtd_ram_real
%defattr(0777,root,root,-)
/etc/munin/plugins/libvirtd_cpus
/etc/munin/plugins/libvirtd_disk_apparent
/etc/munin/plugins/libvirtd_disk_apparent_all
/etc/munin/plugins/libvirtd_disk_real
/etc/munin/plugins/libvirtd_disk_real_all
/etc/munin/plugins/libvirtd_ram_defined
/etc/munin/plugins/libvirtd_ram_real
%defattr(0644,root,root,-)
%config /etc/munin/plugin-conf.d/libvirtd_ram_defined
%config /etc/munin/plugin-conf.d/libvirtd_ram_real

%prep
%setup -q

%build

%install
rm -rf %{buildroot}
make ROOT="%{buildroot}" install

%post
service munin-node restart

%postun
service munin-node restart

%clean
rm -rf %{buildroot}

%changelog
* Mon Mar 23 2015 Thomas Lee <thomlee@iu.edu>
- Version 1.1.
- The graph description now has a statement of the total real resource (RAM,
  CPUs, or disk space) available on the host; the resource listed is the one
  relevant to the plugin (i.e. plugins that have to do with disk space show the
  total disk space on the host allocated to VM disk images).
* Fri Mar 13 2015 Thomas Lee <thomlee@iu.edu>
- Initial RPM build.

