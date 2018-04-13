# Package and version

CWD=$(shell /bin/pwd)
CWD_BASE=$(notdir $(CWD))
PACKAGE=munin_$(CWD_BASE)
SPEC=$(PACKAGE).spec
VERSION=$(shell grep -Ei '^ *Version:' $(PACKAGE).spec | sed -re 's/^ *Version: *//')
RELEASE=$(shell grep "^Release: " $(SPEC) | sed -e "s/^Release: *//")
ARCH=$(shell grep "^BuildArchitectures: " $(SPEC) | sed -e "s/^BuildArchitectures: *//")
PACK_VERS=$(PACKAGE)-$(VERSION)

# Files

PLUGINS=gocipmi_ ipmiget
CONFIGS=gocipmi
CRONTABS=ipmiget

# Where files come from

PLUGIN_SRC=plugins
CONFIG_SRC=config
CRON_SRC=cron

# Where files go to

PLUGIN_DIR=$(ROOT)/opt/share/munin/plugins
SYMLINK_DIR=$(ROOT)/etc/munin/plugins
CONFIG_DIR=$(ROOT)/etc/munin/plugin-conf.d
CRON_DIR=$(ROOT)/etc/cron.d

# Symlinks

SYMLINK_ARGS=fan temp
SYMLINK_BASE=gocipmi_dell
SYMLINKS=$(addprefix $(SYMLINK_BASE)_,$(SYMLINK_ARGS))

# Combined paths

PLUGIN_PATHS=$(addprefix $(PLUGIN_DIR)/,$(PLUGINS))
CONFIG_PATHS=$(addprefix $(CONFIG_DIR)/,$(CONFIGS))
CRON_PATHS=$(addprefix $(CRON_DIR)/,$(CRONTABS))
SYMLINK_PATHS=$(addprefix $(SYMLINK_DIR)/,$(SYMLINKS))

# Binary locations

CP=/bin/cp
FIND=/usr/bin/find
#INSTALL=/usr/bin/install -bDp -o root -g root
INSTALL=/usr/bin/install -bDp
LN=/bin/ln
MKTEMP=/bin/mktemp
MV=/bin/mv
RPMBUILD=/usr/bin/rpmbuild
TAR=/bin/tar

# Tarball

TARBALL=$(PACK_VERS)-$(RELEASE).tgz

# RPM

RPMBD=$(HOME)/rpmbuild
RPMDIRS=$(addprefix $(RPMBD)/RPMS/,$(ARCH))
RPMS=$(addsuffix .rpm,$(addprefix $(PACK_VERS)-$(RELEASE).,$(ARCH)))
RPMPATHS=$(join $(RPMDIRS)/,$(RPMS))

# Where to send RPM

RPMH_SERVER=yum-internal.grid.iu.edu
RPMH_DIR=/opt/var/spool/rpmhopper/new

# Rules

.PHONY=install install_plugin install_symlink install_config install_crontab \
	tarball rpm putrpm uninstall clean

install: install_plugin install_symlinks install_config install_crontab

# Plugin

install_plugin: $(PLUGIN_PATHS)

$(PLUGIN_PATHS): $(PLUGIN_DIR)/%: $(PLUGIN_SRC)/%
	$(INSTALL) -m0755 $^ $@

# Symlink

install_symlinks: $(SYMLINK_PATHS)

$(SYMLINK_PATHS):
	$(INSTALL) -d -m0755 $(SYMLINK_DIR)
	cd $(SYMLINK_DIR); $(LN) -s ../../../opt/share/munin/plugins/gocipmi_ $@

# Config

install_config: $(CONFIG_PATHS)

$(CONFIG_PATHS): $(CONFIG_DIR)/%: $(CONFIG_SRC)/%
	$(INSTALL) -m0644 $^ $@

# Crontab

install_crontab: $(CRON_PATHS)

$(CRON_PATHS): $(CRON_DIR)/%: $(CRON_SRC)/%
	$(INSTALL) -m0644 $^ $@

# Tarball

tarball: $(TARBALL)

$(TARBALL): /tmp/$(TARBALL)
	$(MV) /tmp/$(TARBALL) .

#/tmp/$(TARBALL): 
/tmp/$(TARBALL):
	TEMPDIR=$(shell $(MKTEMP) -d /tmp/gocipmi.XXXXXXXXXX); \
		cd ..; \
		$(CP) -a $(CWD_BASE) $$TEMPDIR/$(PACK_VERS); \
		$(TAR) zcvf /tmp/$(TARBALL) -C $$TEMPDIR --exclude $(PACK_VERS)/$(PACKAGE)-*.tgz $(PACK_VERS); \
		$(RM) -rf $$TEMPDIR

# RPM

rpm: $(RPMPATHS)

$(RPMPATHS): tarball
	$(CP) -p $(TARBALL) $(RPMBD)/SOURCES
	$(RPMBUILD) -ba $(PACKAGE).spec

# Put the RPM(s) where they go

putrpm: $(RPMPATHS)
	scp -p $(RPMPATHS) $(RPMH_SERVER):$(RPMH_DIR)/

# Utility

uninstall:
	$(RM) $(PLUGIN_PATHS) $(SYMLINK_PATHS) $(CONFIG_PATHS) $(CRON_PATHS)

clean:
	$(FIND) . -name '*~' -exec $(RM) {} \;
	$(RM) $(TARBALL) $(RPMPATHS)

