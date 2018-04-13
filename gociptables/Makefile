# Package and version
THISMAKEFILE:=$(lastword $(MAKEFILE_LIST))
THISMAKEFILEPATH:=$(addprefix $(PWD)/,$(THISMAKEFILE))
THISMAKEFILEDIR:=$(dir $(THISMAKEFILEPATH))
SPEC:=$(shell ls $(THISMAKEFILEDIR)/*.spec | head -n 1)
SPECFIND=$(shell sed -n -re '/^[[:space:]]*$(1):/I{s/^[[:space:]]*$(1):[[:space:]]*(.*)[[:space:]]*$$/\1/I;p}' $(SPEC))
PACKAGE:=$(call SPECFIND,name)
VERSION:=$(call SPECFIND,version)
RELEASE:=$(call SPECFIND,release)
ARCH:=$(call SPECFIND,buildarch)
PV:=$(PACKAGE)-$(VERSION)
PVR:=$(PV)-$(RELEASE)
PVRA:=$(PVR).$(ARCH)
SDPV:=iptables-services-goc-$(VERSION)
SDPVR:=$(SDPV)-$(RELEASE)
SDPVRA:=$(SDPVR).$(ARCH)

# Defining the different types of files we have -- where to find them, what
# they're called, where they go

# The initscript
INIT_SRC_DIR:=$(THISMAKEFILEDIR)/init
INIT_FILES:=gociptables
INIT_DEST_DIR:=$(BUILDROOT)/etc/init.d

INIT_SRC_PATHS:=$(addprefix $(INIT_SRC_DIR)/,$(INIT_FILES))
INIT_DEST_PATHS:=$(addprefix $(INIT_DEST_DIR)/,$(INIT_FILES))

# The systemd initscript
SDINIT_SRC_DIR:=$(THISMAKEFILEDIR)/init
SDINIT_FILES:=iptables.init
SDINIT_DEST_DIR:=$(BUILDROOT)/usr/libexec/iptables

SDINIT_SRC_PATHS:=$(addprefix $(SDINIT_SRC_DIR)/,$(SDINIT_FILES))
SDINIT_DEST_PATHS:=$(addprefix $(SDINIT_DEST_DIR)/,$(SDINIT_FILES))

# The config scripts
CONF_SRC_DIR:=$(THISMAKEFILEDIR)/config
CONF_FILES:=00-global-clear 10-global-chains \
	20-global-policies 30-global-rules 90-global-end
CONF_DEST_DIR:=$(BUILDROOT)/etc/iptables.d

CONF_SRC_PATHS:=$(addprefix $(CONF_SRC_DIR)/,$(CONF_FILES))
CONF_DEST_PATHS:=$(addprefix $(CONF_DEST_DIR)/,$(CONF_FILES))

# The non-executable files
AUX_SRC_DIR:=$(THISMAKEFILEDIR)/config
AUX_FILES:=README setup
AUX_DEST_DIR:=$(BUILDROOT)/etc/iptables.d

AUX_SRC_PATHS:=$(addprefix $(AUX_SRC_DIR)/,$(AUX_FILES))
AUX_DEST_PATHS:=$(addprefix $(AUX_DEST_DIR)/,$(AUX_FILES))

# The systemd config file
SDCONF_SRC_DIR:=$(THISMAKEFILEDIR)
SDCONF_FILES:=iptables.service
SDCONF_DEST_DIR:=$(BUILDROOT)/usr/lib/systemd/system

SDCONF_SRC_PATHS:=$(addprefix $(SDCONF_SRC_DIR)/,$(SDCONF_FILES))
SDCONF_DEST_PATHS:=$(addprefix $(SDCONF_DEST_DIR)/,$(SDCONF_FILES))

# The tarball
TARBALL:=$(PVR).tgz
TARBALL_PATH:=$(THISMAKEFILEDIR)/$(TARBALL)

# The RPM
RPMBD:=$(HOME)/rpmbuild
RPMDIRS:=$(addprefix $(RPMBD)/RPMS/,$(ARCH))
RPMS:=$(addsuffix -$(RELEASE).$(ARCH).rpm,$(PV))
SDRPMS:=$(addsuffix -$(RELEASE).$(ARCH).rpm,$(SDPV))
RPMPATHS:=$(foreach rpmdir,$(RPMDIRS),$(addprefix $(rpmdir)/,$(RPMS)))
SDRPMPATHS:=$(foreach rpmdir,$(RPMDIRS),$(addprefix $(rpmdir)/,$(SDRPMS)))

# Where to send RPM
RPMH_SERVER:=yum-internal.grid.iu.edu
RPMH_DIR:=/opt/var/spool/rpmhopper/new
SDRPMH_DIR:=~

###############################################################################
# Rules
###############################################################################

.PHONY: help install install-systemd \
	install-init install-config install-aux \
	install-sdinit install-sdconfig \
	tarball rpm putrpm uninstall clean

# Help message
help:
	@echo "Things you can type:"
	@echo "make help: This message"
	@echo "make tarball: Creates tarball"
	@echo "make rpm: Creates RPM"
	@echo "make clean: Removes all but source files"
	@echo "make install-init (requires root): Installs initscript"
	@echo "make install-config (requires root): Installs config files"
	@echo "make install-aux (requires root): Installs aux files"
	@echo "make install (requires root): Installs everything"
	@echo "make install-sdinit (requires root): Installs initscript, systemd version"
	@echo "make install-sdconfig (requires root): Installs config files, systemd version"
	@echo "make install-systemd (requires root): Installs everything, systemd version"
	@echo "make uninstall (requires root): Removes everything installed"

# Directories
$(sort $(INIT_DEST_DIR) $(SDINIT_DEST_DIR) $(CONF_DEST_DIR) \
	$(SDCONF_DEST_DIR) $(AUX_DEST_DIR)):
	mkdir -p -m0755 $@

# Installation
install: install-init install-systemd install-config install-aux

install-systemd: install-sdinit install-config install-sdconfig install-aux

install-init: $(INIT_DEST_DIR) $(INIT_DEST_PATHS)

install-sdinit: $(SDINIT_DEST_DIR) $(SDINIT_DEST_PATHS)

install-config: $(CONF_DEST_DIR) $(CONF_DEST_PATHS)

install-sdconfig: $(SDCONF_DEST_DIR) $(SDCONF_DEST_PATHS)

install-aux: $(AUX_DEST_DIR) $(AUX_DEST_PATHS)

$(INIT_DEST_PATHS): $(INIT_DEST_DIR)/%: $(INIT_SRC_DIR)/%
	install -m0755 $^ $@

$(SDINIT_DEST_PATHS): $(SDINIT_DEST_DIR)/%: $(SDINIT_SRC_DIR)/%
	install -m0755 $^ $@

$(CONF_DEST_PATHS): $(CONF_DEST_DIR)/%: $(CONF_SRC_DIR)/%
	install -m0744 $^ $@

$(SDCONF_DEST_PATHS): $(SDCONF_DEST_DIR)/%: $(SDCONF_SRC_DIR)/%
	install -m0644 $^ $@

$(AUX_DEST_PATHS): $(AUX_DEST_DIR)/%: $(CONF_SRC_DIR)/%
	install -m0644 $^ $@

# Tarball
tarball: $(TARBALL_PATH)

$(TARBALL_PATH): /tmp/$(TARBALL)
	@mv /tmp/$(TARBALL) $(THISMAKEFILEDIR)

/tmp/$(TARBALL): $(INIT_SRC_PATHS) $(SDINIT_SRC_PATHS) $(CONF_SRC_PATHS) \
	$(SDCONF_SRC_PATHS) $(AUX_SRC_PATHS) $(THISMAKEFILEPATH) $(SPEC)
	@echo "*** Creating $(TARBALL_PATH) ..."
	@TEMPDIR=$(shell mktemp -d /tmp/$(PACKAGE)make.XXXXXXXXX); \
		pushd $$TEMPDIR >/dev/null; \
		cp -a $(THISMAKEFILEDIR) $(PV); \
		tar zcf /tmp/$(TARBALL) --exclude "*.tgz" --exclude ".svn" --exclude "*~" $(PV); \
		popd >/dev/null; \
		rm -rf $$TEMPDIR
	@echo "*** $(TARBALL_PATH) created."

# RPM
rpm: $(RPMPATHS)

$(RPMPATHS): tarball
	@echo "*** Building RPM ..."
	@cp -p $(TARBALL_PATH) $(RPMBD)/SOURCES
	@rpmbuild -ba $(SPEC)
	@echo "*** RPM build complete."

# Put the RPMs where they go
putrpm: $(RPMPATHS) $(SDRPMPATHS)
	scp -p $(RPMPATHS) $(RPMH_SERVER):$(RPMH_DIR)/
	scp -p $(SDRPMPATHS) $(RPMH_SERVER):$(SDRPMH_DIR)/

# Utility
uninstall: $(INIT_DEST_PATHS) $(SDINIT_DEST_PATHS) $(CONF_DEST_PATHS) \
	$(SDCONF_DEST_PATHS) $(AUX_DEST_PATHS) $(INIT_DEST_DIR) \
	$(CONF_DEST_DIR) $(AUX_DEST_DIR)
	rm -f $(INIT_DEST_PATHS) $(CONF_DEST_PATHS) $(AUX_DEST_PATHS)
	for d in $(sort $(INIT_DEST_DIR) $(CONF_DEST_DIR) $(AUX_DEST_DIR)); do \
		if ! ls $$d >&/dev/null; then \
			rmdir $$d; \
		fi; \
	done

clean:
	find $(THISMAKEFILEDIR) -name '*~' -delete
	find $(THISMAKEFILEDIR) -name '*.tgz' -delete
	rm -f $(RPMPATHS)
