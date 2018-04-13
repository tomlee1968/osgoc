# Package and version
THISMAKEFILE:=$(lastword $(MAKEFILE_LIST))
#$(info This Makefile: $(THISMAKEFILE))
THISMAKEFILEPATH:=$(addprefix $(PWD)/,$(THISMAKEFILE))
#$(info Path of this Makefile: $(THISMAKEFILEPATH))
THISMAKEFILEDIR:=$(dir $(THISMAKEFILEPATH))
#$(info Directory containing this Makefile: $(THISMAKEFILEDIR))
SPEC:=$(shell ls $(THISMAKEFILEDIR)*.spec | head -n 1)
#$(info Spec file for this package: $(SPEC))
SPECFIND=$(shell sed -n -re '/^[[:space:]]*$(1):/I{s/^[[:space:]]*$(1):[[:space:]]*(.*)[[:space:]]*$$/\1/I;p}' $(SPEC))
PACKAGE:=$(call SPECFIND,name)
VERSION:=$(call SPECFIND,version)
RELEASE:=$(call SPECFIND,release)
ARCH:=$(call SPECFIND,buildarch)
PV:=$(PACKAGE)-$(VERSION)
PVR:=$(PV)-$(RELEASE)
PVRA:=$(PVR).$(ARCH)
$(info Package/version/release/arch: $(PVRA))

# Defining the different types of files we have -- where to find them, what
# they're called, where they go

# The plugins
PLUG_SRC_DIR:=$(THISMAKEFILEDIR)
PLUG_FILES:=libvirtd_cpus libvirtd_disk_apparent libvirtd_disk_apparent_all \
	libvirtd_disk_real libvirtd_disk_real_all libvirtd_ram_defined \
	libvirtd_ram_real
PLUG_DEST_DIR:=$(ROOT)/opt/share/munin/plugins

PLUG_SRC_PATHS:=$(addprefix $(PLUG_SRC_DIR)/,$(PLUG_FILES))
PLUG_DEST_PATHS:=$(addprefix $(PLUG_DEST_DIR)/,$(PLUG_FILES))

# The config files
CONF_SRC_DIR:=$(THISMAKEFILEDIR)
CONF_FILES:=libvirtd_ram_defined libvirtd_ram_real
CONF_DEST_DIR:=$(ROOT)/etc/munin/plugin-conf.d

CONF_SRC_PATHS:=$(addprefix $(CONF_SRC_DIR)/,$(addsuffix .conf,$(CONF_FILES)))
CONF_DEST_PATHS:=$(addprefix $(CONF_DEST_DIR)/,$(CONF_FILES))

# Links
LINK_DIR:=$(ROOT)/etc/munin/plugins

LINK_PATHS:=$(addprefix $(LINK_DIR)/,$(PLUG_FILES))

# The relative path from $(LINK_DIR) to $(PLUG_DEST_DIR)
REL_PATH:=../../../opt/share/munin/plugins

# Tarball
TARBALL:=$(PVR).tgz
TARBALL_PATH:=$(THISMAKEFILEDIR)/$(TARBALL)

# RPM
RPMBD:=$(HOME)/rpmbuild
RPMDIRS:=$(addprefix $(RPMBD)/RPMS/,$(ARCH))
RPMS:=$(addsuffix -$(RELEASE).$(ARCH).rpm,$(PV))
RPMPATHS:=$(foreach rpmdir,$(RPMDIRS),$(addprefix $(rpmdir)/,$(RPMS)))

# Where to send RPM
RPMH_SERVER:=yum-internal.grid.iu.edu
RPMH_DIR:=/opt/var/spool/rpmhopper/new

###############################################################################
# Rules
###############################################################################

.PHONY: help install \
	install-plugins install-links install-conf \
	tarball rpm putrpm uninstall clean

# Help message
help:
	@echo "Things you can type:"
	@echo "make help: This message"
	@echo "make tarball: Creates tarball"
	@echo "make rpm: Creates RPM"
	@echo "make putrpm: Installs RPM on $(RPMH_SERVER)"
	@echo "make clean: Removes all but source files"
	@echo "make install-plugins (requires root): Installs plugins"
	@echo "make install-config (requires root): Installs config files"
	@echo "make install-links (requires root): Installs links"
	@echo "make install (requires root): Installs everything"
	@echo "make uninstall (requires root): Removes everything installed"

$(sort $(PLUG_DEST_DIR) $(CONF_DEST_DIR) $(LINK_DIR)):
	mkdir -p -m0755 $@

# Installation
install: install-plugins install-links install-conf

# Plugin installation
install-script: $(PLUG_DEST_DIR) $(PLUG_DEST_PATHS)

$(PLUG_DEST_PATHS): $(PLUG_DEST_DIR)/%: $(PLUG_SRC_DIR)/%
	install -m0755 $^ $@

# Making links
install-links: $(LINK_DIR) $(PLUG_DEST_DIR) $(PLUG_DEST_PATHS) $(LINK_PATHS)

$(LINK_PATHS): $(LINK_DIR)/%: $(PLUG_DEST_DIR)/%
	ln -s $(REL_PATH)/$(notdir $<) $@

# Config file installation
install-conf: $(CONF_DEST_DIR) $(CONF_DEST_PATHS)

$(CONF_DEST_PATHS): $(CONF_DEST_DIR)/%: $(CONF_SRC_DIR)/%.conf
	install -m0744 $^ $@

# Tarball
tarball: $(TARBALL_PATH)

$(TARBALL_PATH): /tmp/$(TARBALL)
	@mv /tmp/$(TARBALL) .

/tmp/$(TARBALL): $(PLUG_SRC_PATHS) $(CONF_SRC_PATHS) $(THISMAKEFILEPATH) $(SPEC)
	@echo "*** Creating $(TARBALL_PATH) ..."
	@TEMPDIR=$(shell mktemp -d /tmp/$(PACKAGE)make.XXXXXXXXXX); \
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

# Put the RPM(s) where they go
putrpm: $(RPMPATHS)
	scp -p $(RPMPATHS) $(RPMH_SERVER):$(RPMH_DIR)/

# Utility
uninstall: $(PLUG_DEST_PATHS) $(CONF_DEST_PATHS) $(PLUG_DEST_DIR) $(CONF_DEST_DIR) $(LINK_DIR)
	rm -f $(PLUG_DEST_PATHS) $(LINK_PATHS) $(CONF_DEST_PATHS)
	for d in $(sort $(PLUG_DEST_DIR) $(CONF_DEST_DIR) $(LINK_DIR)); do \
		if ! ls $$d >&/dev/null; then \
			rmdir $$d; \
		fi; \
	done

clean:
	find $(THISMAKEFILEDIR) -name '*~' -delete
	find $(THISMAKEFILEDIR) -name '*.tgz' -delete
	rm -f $(RPMPATHS)
