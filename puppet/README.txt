OSG Operations Puppet Rules

Tom Lee <thomlee@iu.edu>, OSG Operations sysadmin
This document last modified 2016-02-01

OSG Operations uses Puppet for configuration management, and the files in this
repository define OSG Operations' Puppet setup.

Introduction
============

Puppet's configuration language organizes specific rules for how things should
be on a system (which it calls "resources") into rule sets (which it calls
"classes").  It also defines sets of systems (which it calls "nodes") that
should be affected by this or that class (the sum total of the rules that will
affect a given client system is called a "catalog").  Bear with me.  Puppet's
entities are not well named.

Environments
============

What's more, an individual system can decide that it's going to get a
completely different set of configuration files from the Puppet server.  It
does this by defining its "environment" -- this is just a string, a name of a
subdirectory of /etc/puppet/env on the client system.  You can define whatever
and as many environments as you want, as long as you make sure that if the
client asks for environment X, there's a /etc/puppet/env/X on the server, but
Puppet comes with three environments predefined: "development", "testing", and
"production".  It turns out that these are pretty close to what we need, so
those are what we're using.

On the client, you define the top-level directory for the environments in the
/etc/puppet/puppet.conf file:

[main]
    environmentpath = $confdir/env

You must then make sure that within that "environmentpath" directory, there is
a subdirectory for each environment the clients will be looking for
(e.g. $confdir/env/development).

The environment.conf file can also define "modulepath", a directory from which
other files can be easily included.  Each environment has a "modules" directory
(e.g. $confdir/env/development/modules), each subdirectory of which can be
considered a module.  Puppet's default is to look within the "modules"
directory -- each module has its own "manifests" subdirectory, and Puppet will
look for and execute "init.pp" in that subdirectory
(e.g. $confdir/env/development/modules/mymodule/manifest/init.pp).  If you
define "modulepath" in environment.conf you can have Puppet read a different
file instead.

Main Manifests Directory
========================

The "manifest" is the file containing Puppet configuration language code for
both what needs to be done and what client systems it needs to be done on.  You
could in theory put all your Puppet configuration in that file, and it would
work, but you shouldn't do that.  By default Puppet will look for a directory
within the environment directory called "manifests"
(e.g. $confdir/env/development/manifests) and execute every .pp file it finds
in it, in alphabetical order.  If you don't want it to do that, you'll have to
tell it where the manifest file is.  Within the environment subdirectory, there
can be an optional environment.conf file
(e.g. $confdir/env/development/environment.conf) defining certain configuration
options -- only a few are allowed, but one of them is "manifest":

manifest = manifests/site.pp

It is common practice to do that, by which I mean to use a file called
"site.pp" within the environment's manifests directory as the main manifest
file.

The site.pp file (or whatever you call it) contains many "node" statements,
defining which classes should apply to which client systems.  The syntax for
defining resources, classes and nodes is beyond the scope of this document, but
fortunately their syntax is not site-dependent.  Refer to the appropriate
Puppet documentation for those details.

Environments and Version Control
================================

This really couldn't be any simpler.  On the Puppet server, the Puppet
configuration repository you're looking at needs to be checked out of SVN, Git,
or whatever other version control system you're using, three times: once for
development, once for testing, and once for production.  This is how they are
currently checked out and defined:

/etc/puppet/env/development: development
/etc/puppet/env/testing: testing
/etc/puppet/env/production: production

The appropriate configuration has been done in the server's
/etc/puppet/puppet.conf file to define these as the locations for the three
environments' manifests and modules.

When making a change to the Puppet rules, make it in the development
environment first, because your changes are live: these are the environment
directories the Puppet server is using right now.  Then go to a client system
that uses the "development" environment (puppet-test.grid.iu.edu exists solely
for this purpose) and test the catalog with the command "puppet agent -t".  Fix
any problems you find, and if there aren't any, you can check the changes into
version control.

Then, once it's time to put those onto the ITB servers, cd to the testing
environment and check the changes out of version control.  The changes are now
live on any client systems using the "testing" environment.  The next time
Puppet runs on each of those client systems, they'll get your new
changes. Likewise, when it's time to make the changes live on the production
servers, cd to the production directory and check out the changes from version
control.

Our Modules, or Where Should Changes Go?
========================================

Puppet modules are designed for organizing the classes in some way.  Some
choose to organize them by service (everything related to, say, MySQL is
located in one module), while others organize them topically, which is what we
do.  Our modules aren't designed for sharing with other sites, but that's
because we're not an OSG site and don't do even the same kinds of things they
do.

If you're going to add something to Puppet, think carefully, and remember that
anything you add is going to be run by about 200 systems 48 times a day.
That's 5000 chances to screw up daily.

"A computer lets you make more mistakes faster than any other invention with
the possible exceptions of handguns and Tequila."

					-- Mitch Ratcliffe

Also, our primary goal in any of this is rapid deployment for disaster
recovery.  If a service goes down, we must be able to rebuild it as fast as
possible.  When a production service is down, there's no time for fiddling or
experimenting to get something working.  And don't let me hear anyone saying,
"Well, that hardly ever happens," or even "That's never happened."  The point
of this is that the chances of disaster are always nonzero.  We must ALWAYS be
thinking of what we're going to do when disaster occurs, because eventually it
will, and until it happens, we won't know where, when or why.

If there's any change or customization that needs to be made to a stock distro,
there are basically four ways it can happen.

1. Doing it by hand: You can just ssh to the machine and make the change.  This
isn't very practical, for two reasons: first, it isn't scalable -- you will
often have to make the same change to many systems, if not all of them, and the
more machines you have to deal with, the more of your time it will eat.  And if
for some reason you think you have plenty of time, you're not thinking of the
right situation.  Think about an occasion when multiple production systems are
down and they all need to be brought back up YESTERDAY.  That's when
scalability is important.  Second, it's ephemeral -- if the VM dies in flames,
your by-hand changes will be gone, so you'll have to recreate them by hand, if
you can even remember what you did.  There are much better ways.  Throw this
one out; use one of the others.

2. Building it into the stemcell image: We have stemcell images for a reason.
To make a stemcell image, we just install a stock distro on a VM, then use
scripts to customize it, then shut it down and archive its disk image.  The
advantages to this: First, it's much faster to unpack an archive than it is to
install a stock distro.  Second, it's even faster if the basic changes that all
our systems need are already baked into the archived VM, rather than having to
make those changes later on each individual system.  Remember that our goal is
rapid deployment.  That said, there are changes that are specific to certain
services, and once the VM is installed, any further changes to the stemcell
image can't affect it anymore.

3. Putting it into a service's install script(s): We have scripts that can turn
a base stemcell image into an instance of a given service automatically.
Additionally, some of those scripts run on every installed service.  If there
are changes that need to be made based on what service is being installed, this
is the perfect place to put them.  Changes that need to be made to all hosts
are probably best put somewhere else, however -- not everything has an install
script (as much as we urge, prod and cajole everyone to write and test an
install script for every service), so it's not guaranteed that the changes will
happen.  Also, again, once the service is installed, any further changes to the
install script can't affect it anymore.

4. Writing a Puppet rule: This is great for changes that must happen to systems
after they've been installed (like new changes that weren't in stemcell or
install scripts when the systems were set up), changes that are constantly
happening (like certificates getting renewed), and changes that must remain
synchronized across all systems (like firewall configurations).  The drawback
to adding a Puppet rule is that every rule slows down every host a bit.

As I see it, Puppet should only be used for "Puppetlike" things.  A change is
"Puppetlike" if ...

A. ... it's very important to the operation of the entire system, especially if
it's got a history of being changed, either by rogue processes or by
well-meaning but mistaken sudoers.  The global firewall files are an example of
this, and so is keeping sshd up; without these things it may become impossible
to connect to the system.

B. ... it's something that can only be done by Puppet.  Examples of this
include the warning prompt telling you that you're logged in as root on a
production system (that depends on what Puppet environment the system is using,
so there's nothing else that can do this) and the Munin plugins that monitor
network traffic based on the system's IP addresses (this could also be put in
install scripts, but then it would only work on systems on which install
scripts had been run).

C. ... it's something that is expected to change over time.  Examples of this
are the user SSH keys (people are always changing their keys), the list of CRLs
(these change frequently and without warning), or the GOC user certificate
(this must be renewed each year).  There's no other way to keep changes like
these up to date -- putting them in the stemcell images or install scripts
would be ineffective.

D. ... it's temporary.  If a new change has to be made on all systems, the
first thing to do is to make a temporary Puppet rule making the change on
currently-running systems (obviously you should do this on the test server
first, then the ITB servers, and then you should only check out the change onto
the production environment on a production maintenance day).  After that, the
change should be moved either to the stemcell or to the install scripts.  Once
new stemcell images have been built that include the change, or once the
install scripts including the change have been checked into version control,
the temporary Puppet rule can be removed.

The Puppet modules we currently have are:

* certificates -- for certificates (such as the GOC user certificate) that need
  to be on all (or at least many) systems.

* config -- for ensuring that certain configuration files (such as the global
  firewall files) are consistent across all (or at least many) systems.

* globals -- for certain global settings that are used by other modules

* packages -- for packages that need to be installed on certain systems.
  However, packages that need to be installed everywhere are installed in the
  stemcell image, and packages needed for particular services are installed by
  those services' install scripts.  This is used only for keeping
  locally-created packages up to date, such as the vmtool and osupdate
  packages.

* security-test -- this special module is for when the OSG security team sends
  out an announcement to look for signs of a rootkit or other security breach.
  It synchronizes a script that searches for the telltales mentioned in the
  announcements, and makes sure that script runs regularly.

* services -- makes sure that certain system services (we're talking about
  daemons here, such as portmap/portreserve, sshd, etc.) are enabled/disabled
  and running/stopped globally.  As with packages, most services that need to
  be enabled and running (or disabled and stopped) are so defined in the
  stemcell images, or are handled by the service-based install scripts if
  services depend on them (or depend on their being absent).  However, there is
  some software (and some users with sudo privileges) that like to fiddle with
  enabling and disabling services, and that can cause problems.  This module is
  designed to keep services down that should stay down, and keep services up
  that should stay up.

* ssh_userkeys -- synchronizes SSH user public keys across all systems so our
  staff can log in.

* temp -- this is where you put temporary Puppet rules whose effects will later
  be moved to stemcell kickstart files or service install scripts.
