Summary: OS update scripts
Name: osupdate
Version: 1.32
Release: 1
License: GPL
Group: System Environment/Base
URL: http://internal.grid.iu.edu/
Source0: %{name}-%{version}-%{release}.tgz
BuildArch: noarch
Requires: yum
Obsoletes: osupdate-client, osupdate-server

%global _binary_filedigest_algorithm 1
%global _source_filedigest_algorithm 1

%description
This script simplifies the GOC OS update procedure for its hosts.

%files
%defattr(0744,root,root,-)
/opt/sbin/osupdate

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
* Tue Oct 24 2017 Thomas Lee <thomlee@iu.edu> -
- Version 1.32.
- Added a few messages to indicate when the script is running rpmconf and
  puppet, and when it is done, so it does not look as if it is hanging.
* Tue Jul 19 2016 Thomas Lee <thomlee@iu.edu> -
- Version 1.31.
- Installs rpmconf if not installed.
- Checks rpmconf version to see whether it supports the -c and --frontend
  options before attempting to use them.
* Tue May 24 2016 Thomas Lee <thomlee@iu.edu> -
- Version 1.30.
- Put rpmconf and puppet steps in osupdate rather than in all_updates.pl.
- Changed puppet so that it only actually runs Puppet if it has not run in the
  past 30 minutes.
* Wed Jan 20 2016 Thomas Lee <thomlee@iu.edu> -
- Version 1.29.
- Added "--skip-broken" to all yum updates.  This avoids a lot of issues.
* Wed Dec 02 2015 Thomas Lee <thomlee@iu.edu> -
- Version 1.28.
- Discovered that I was using "today" instead of "$today" in PREVFILE, causing
  the "previous_versions_..." file to be undated.
- Added DONEFILE, which is zero in size, but this script updates its
  modification time when it finishes, indicating to other scripts when this
  script most recently completed its updates on this machine.
* Mon Sep 14 2015 Thomas Lee <thomlee@iu.edu> -
- Version 1.27.
- Apparently the EPEL change back in February (see notes for version 1.26,
  below) later caused a problem when some packages from EPEL updated packages
  on the glidein servers, so I added some exclusions in the case that we are
  updating a glidein server.  Jeff Dost of UCSD supplied the list of packages
  to exclude.
  * Tue Feb 24 2015 Thomas Lee <thomlee@iu.edu> -
- Version 1.26.
- Added a number of excludes to the BDII server case -- apparently when I added
  more packages to our local EPEL mirror, some of them were upgrades to
  packages that BDII has, but these upgrades break BDII.
- Tired of the wildcard problem, I changed it to just create a tempdir and cd
  to it, so there will never be files in the CWD that match any wildcards.
* Wed Feb 18 2015 Thomas Lee <thomlee@iu.edu> -
- Version 1.25.
- Got rid of using noglob option to prevent bash from expanding wildcards in
  repo names; just being careful to quote and escape when necessary instead.
- Instead of excluding globus* whenever we detect that there is an OSG
  globus-common present (which broke when people started using the EPEL
  globus-common), we now detect and exclude any OSG packages from updates.
  This is better anyway, because excluding globus* was excluding some actual
  updates.
- Renamed $PRELUDEDIR to $PLUGINDIR, because it makes more sense.
- Added a security check to pre/post-update scripts: $PLUGINDIR must be owned
  by root, must not be writable by a nonroot group, and must not be
  world-writable, or we will ignore it.  Also, we skip any file in that
  directory that does not meet those same criteria.
- Enforced consistent use of [[ ]] rather than [ ].
* Fri Dec 19 2014 Thomas Lee <thomlee@iu.edu> -
- Version 1.24.
- Being a lot more careful with noglob, which was preventing
  preupdate/postupdate scripts from being detected.
- Moved the distro/version detection into setup_things, so the settings section
  has only actual settings in it.
- Test mode (-t option) really doesn't do anything now; it doesn't even clean
  the caches.  It just prints messages.
* Tue Oct 28 2014 Thomas Lee <thomlee@iu.edu> -
- Version 1.23.
- Now able to detect CentOS and its version and adjust accordingly.
- Excludes globus* from update if globus-common is an OSG release (for irods).
* Fri Mar 07 2014 Thomas Lee <thomlee@iu.edu> -
- Version 1.22.
- Previous versions of osupdate were setting "set -o noglob", which interferes
  with a lot of bash functionality, none of which we were actually using until
  version 1.21.  Now osupdate restores the original value of the noglob setting
  (it is off by default) when it is done with whatever it needs it turned on
  for.
* Wed Mar 05 2014 Thomas Lee <thomlee@iu.edu> -
- Version 1.21.
- Added osupdate pre/postlude script support.  If there are any executable
  files in /opt/etc/osupdate.d/ ending in .preupdate, run them before doing
  other OS update tasks.  Likewise, run executables in that directory ending in
  .postupdate after doing other OS update tasks.  If if the directory doesn't
  exist or has no executable scripts in it, do nothing at those points.  Some
  services/instances need certain tasks done (for example, rebuilding kernel
  modules after a kernel update) before after an OS update occurs; this
  provides an automated means for that to happen.
* Tue Jun 18 2013 Thomas Lee <thomlee@iu.edu> -
- Version 1.20.
- Changed Dell firmware update process more.  This time we completely clean up
  after ourselves after doing a firmware update.
- Also improved the tests to see whether we should do a firmware update --
  whether we're on a physical server, and whether that server is a Dell one (I
  suppose we could add more code in the future to deal with other vendors).
* Tue Feb 19 2013 Thomas Lee <thomlee@iu.edu> -
- Version 1.19.
- Changed Dell firmware update process to work around Dell's problems.
* Fri Nov 09 2012 Thomas Lee <thomlee@iu.edu> -
- Version 1.18.
- Attempted to quell error messages that always occur when updating to the
  latest goc-internal-repo RPM -- rather than always updating against the
  symlinked latest package, it only accesses that if the package isn't
  installed at all.  Otherwise, it just updates against the YUM repo.
- Attempted to quell another error message that always occurs since we removed
  the RHN YUM plugin from all servers that aren't RHEL satellite mirrors.
  There's no reason to disable the RHN plugin when there's no RHN plugin.
* Tue Sep 11 2012 Thomas Lee <thomlee@iu.edu> -
- Version 1.17.
- Doesn't do the Dell firmware update with -t specified.
- Creates /opt/var if it doesn't exist, and not just /opt/var/osupdate.
* Tue Jul 17 2012 Thomas Lee <thomlee@iu.edu> -
- Version 1.16.
- Also updates the Dell OpenManage and firmware RPMs, if this is a physical
  Dell server, and also updates the firmware in that case.
* Mon May 14 2012 Thomas Lee <thomlee@iu.edu> -
- Version 1.15.
- Will make sure the latest goc-internal-repo RPM is installed.
* Tue May 1 2012 Thomas Lee <thomlee@iu.edu> -
- Version 1.14.
- Determined arch will no longer be i586, i686, etc -- if it ends in 86, it
  will be i386.  There is no rhel-i686-server-5 distro and no rhel-i686-5 repo;
  it's always i386.
* Tue Apr 17 2012 Thomas Lee <thomlee@iu.edu> -
- Version 1.13.
- Will always update from goc-epel-<arch>-<version>.
- Script now determines arch, variant and version rather than hardcoding.
- No longer fileglobs the openssl exclude for BDII servers.
- Reversed -c option such that noncached updating is the default.
- No longer osupdate-client and osupdate-server.
* Tue Sep 20 2011 Thomas Lee <thomlee@iu.edu> -
- Version 1.12.
- Removed osupdate-scheduler and osupdate-yum cron jobs.
- Added reliance on yum-internal repository instead.
* Tue Jul 26 2011 Thomas Lee <thomlee@indiana.edu> -
- Version 1.11.
- Removed the single-quoting that was added in 1.9.  This apparently causes
  excludes and includes to silently fail.  It's a damned-if-you-do,
  damned-if-you-don't situation; there had just better not be files in the CWD
  that match the wildcard.
* Wed Jun 15 2011 Thomas Lee <thomlee@indiana.edu> -
- Version 1.10.
- Fixed an error in is_blackout_week that caused blackout week to start a week
  early if the month began on a Wednesday (or more generally on the day of the
  week after the $DOW setting).
* Wed Jun 08 2011 Thomas Lee <thomlee@indiana.edu> -
- Version 1.9.
- Single-quoted all wildcards in the yum command line wherever they occurred.
  If there are files in the current working directory that match the wildcard,
  they will be expanded, causing yum to experience syntax errors.
* Tue May 24 2011 Thomas Lee <thomlee@indiana.edu> -
- Version 1.8.
- Similar to the one in osupdate-yum (see version 1.5 below), I added an
  exclusion of c-ares and boost to osupdate when the bdii package is present.
- Added a "-a" option to osupdate to disable this exclusion if desired.
- Added openldap* to the exclusions in osupdate-yum and osupdate when bdii is
  present.  This is because openldap tends to change radically between even
  minor versions, enough that bdii stops working.
* Tue May 10 2011 Thomas Lee <thomlee@indiana.edu> -
- Version 1.7.
- Dropped lockfile mechanism in favor of separate 'gocloc' package.
* Thu Apr 07 2011 Thomas Lee <thomlee@indiana.edu> -
- Version 1.6.
- Since yum doesn't create its lockfile until some time after it runs, if at
  all, we have to use our own lockfile, along with the PID and staleness
  checking that goes along with that.
* Tue Apr 05 2011 Thomas Lee <thomlee@indiana.edu> -
- Version 1.5.
- Excluding 'boost' and 'c-ares' packages if 'bdii' package is present -- this
  is because BDIIv4 servers have their own special versions of those packages,
  and trying to do a generic 'yum update', even a '--downloadonly' one, fails
  with depsolving problems on BDIIv4 servers as a result.
* Tue Mar 29 2011 Thomas Lee <thomlee@indiana.edu> -
- Version 1.4.
- Changed osupdate-scheduler so the /etc/cron.d/osupdate-yum it creates will
  run an actual script (the added osupdate-yum script) rather than trying to
  pack the whole command into a crontab file.
- The osupdate-yum script is more commented and, I hope, more readable than
  the crontab one-liner I used to have, but it also makes sure the yum lockfile
  clears before it runs.  We're no longer sending all output to /dev/null, so
  with any luck this should prevent yum from generating complaints unless there
  really is a significant problem.
* Wed Mar 23 2011 Thomas Lee <thomlee@indiana.edu> -
- Version 1.3.
- Added the '-q' option to the 'yum clean all' command in osupdate-scheduler.
  If we don't keep yum quiet, it will generate a root email from every server.
- Changed a "-le" to a "-lt" in is_blackout_week, with the result that the
  blackout period is actually LENGTH days long, rather than LENGTH+1 days.
  Changed the comments to reflect this.  Also increased LENGTH to make the
  blackout period a day longer.
* Mon Feb 23 2011 Thomas Lee <thomlee@indiana.edu> -
- Version 1.2.
- Added the '-c' option to osupdate to allow a non-cached update if necessary.
- Fixed up some of the comment documentation in osupdate.
- Changed the repository exclusion/inclusion language to exclude everything
  but Redhat repositories.  This was after a repository file, located only on
  one server and set enabled, caused an update of a package because the
  repository maintainers decided to reorganize, and this took down a production
  service.
* Mon Jan 31 2011 Thomas Lee <thomlee@indiana.edu> -
- Version 1.1-2.
- Silenced the yum --downloadonly cron job so it won't generate root email.
* Mon Jan 31 2011 Thomas Lee <thomlee@indiana.edu> -
- Version 1.1-1.
- Using yum-downloadonly instead of yum-updatesd.
* Mon Jan 31 2011 Thomas Lee <thomlee@indiana.edu> -
- Version 1.0-2.
- Apparently it was #!bin/bash in osupdate-scheduler instead of #!/bin/bash.
* Mon Jan 31 2011 Thomas Lee <thomlee@indiana.edu> - 
- Initial build.
