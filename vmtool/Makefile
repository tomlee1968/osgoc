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

# Defining the different types of files we have -- where to find them, what
# they're called, where they go

# The script
SCR_SRC_DIR:=$(THISMAKEFILEDIR)
SCR_FILES:=vmtool.pl
SCR_DEST_DIR:=$(ROOT)/opt/sbin

SCR_SRC_PATHS:=$(addprefix $(SCR_SRC_DIR)/,$(SCR_FILES))
SCR_DEST_PATHS:=$(addprefix $(SCR_DEST_DIR)/,$(SCR_FILES))

# The module(s)
MOD_SRC_DIR:=$(THISMAKEFILEDIR)
MOD_FILES:=DataAmount.pm
MOD_DEST_DIR:=$(ROOT)/usr/share/perl5

MOD_SRC_PATHS:=$(addprefix $(MOD_SRC_DIR)/,$(MOD_FILES))
MOD_DEST_PATHS:=$(addprefix $(MOD_DEST_DIR)/,$(MOD_FILES))

# The config file
CONF_SRC_DIR:=$(THISMAKEFILEDIR)
CONF_FILES:=vmtool.config
CONF_DEST_DIR:=$(ROOT)/opt/etc

CONF_SRC_PATHS:=$(addprefix $(CONF_SRC_DIR)/,$(CONF_FILES))
CONF_DEST_PATHS:=$(addprefix $(CONF_DEST_DIR)/,$(CONF_FILES))

# The initscript
INIT_SRC_DIR:=$(THISMAKEFILEDIR)
INIT_FILES:=gocvmwhosua
INIT_DEST_DIR:=$(ROOT)/etc/rc.d/init.d

INIT_SRC_PATHS:=$(addprefix $(INIT_SRC_DIR)/,$(INIT_FILES))
INIT_DEST_PATHS:=$(addprefix $(INIT_DEST_DIR)/,$(INIT_FILES))

# The completions script
COMP_SRC_DIR:=$(THISMAKEFILEDIR)
COMP_FILES:=vmtool_completions.sh
COMP_DEST_DIR:=$(ROOT)/etc/profile.d

COMP_SRC_PATHS:=$(addprefix $(COMP_SRC_DIR)/,$(COMP_FILES))
COMP_DEST_PATHS:=$(addprefix $(COMP_DEST_DIR)/,$(COMP_FILES))

# Links
LINKS:=allvm autovm buildvm cpvm exportvm importvm lsvm merge_all_snapshots mkvm mvvm noautovm rebuild_stemcell rebuild_vmware rmvm swapvm vmup vmdown

LINK_PATHS:=$(addprefix $(SCR_DEST_DIR)/,$(LINKS))

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
	install-script install-links install-conf install-initscript \
	install-comps \
	tarball rpm putrpm uninstall clean

# Help message
help:
	@echo "Things you can type:"
	@echo "make help: This message"
	@echo "make tarball: Creates tarball"
	@echo "make rpm: Creates RPM"
	@echo "make putrpm: Installs RPM on $(RPMH_SERVER)"
	@echo "make clean: Removes all but source files"
	@echo "make install-script (requires root): Installs main script"
	@echo "make install-initscript (requires root): Installs initscript"
	@echo "make install-config (requires root): Installs config files"
	@echo "make install-links (requires root): Installs links"
	@echo "make install-comps (requires root): Installs bash completion script"
	@echo "make install (requires root): Installs everything"
	@echo "make uninstall (requires root): Removes everything installed"

$(sort $(SCR_DEST_DIR) $(MOD_DEST_DIR) $(CONF_DEST_DIR) $(INIT_DEST_DIR) $(COMP_DEST_DIR)):
	mkdir -p -m0755 $@

# Installation
install: install-script install-mods install-links install-conf install-initscript install-comps

# Script installation
install-script: $(SCR_DEST_DIR) $(SCR_DEST_PATHS)

$(SCR_DEST_PATHS): $(SCR_DEST_DIR)/%: $(SCR_SRC_DIR)/%
	install -m0755 $^ $@

# Module installation
install-mods: $(MOD_DEST_DIR) $(MOD_DEST_PATHS)

$(MOD_DEST_PATHS): $(MOD_DEST_DIR)/%: $(MOD_SRC_DIR)/%
	install -m0644 $^ $@

# Making links
install-links: $(SCR_DEST_DIR) $(SCR_DEST_PATHS)
	cd $(SCR_DEST_DIR); for i in $(LINKS); do ln -s $(SCR_FILES) $$i; done

# Config file installation
install-conf: $(CONF_DEST_DIR) $(CONF_DEST_PATHS)

$(CONF_DEST_PATHS): $(CONF_DEST_DIR)/%: $(CONF_SRC_DIR)/%
	install -m0744 $^ $@

# Initscript installation
install-initscript: $(INIT_DEST_DIR) $(INIT_DEST_PATHS)

$(INIT_DEST_PATHS): $(INIT_DEST_DIR)/%: $(INIT_SRC_DIR)/%
	install -m0755 $^ $@

# Completion script installation
install-comps: $(COMP_DEST_DIR) $(COMP_DEST_PATHS)

$(COMP_DEST_PATHS): $(COMP_DEST_DIR)/%: $(COMP_SRC_DIR)/%
	install -m0644 $^ $@

# Tarball
tarball: $(TARBALL_PATH)

$(TARBALL_PATH): /tmp/$(TARBALL)
	@mv /tmp/$(TARBALL) .

/tmp/$(TARBALL): $(SCR_SRC_PATHS) $(INIT_SRC_PATHS) $(CONF_SRC_PATHS) $(COMP_SRC_PATHS) $(THISMAKEFILEPATH) $(SPEC)
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
uninstall: $(SCR_DEST_PATHS) $(INIT_DEST_PATHS) $(CONF_DEST_PATHS) $(SCR_DEST_DIR) $(INIT_DEST_DIR) $(CONF_DEST_DIR)
	rm -f $(SCR_DEST_PATHS) $(LINK_PATHS) $(CONF_DEST_PATHS) $(INIT_DEST_PATHS) $(COMP_DEST_PATHS)
	for d in $(sort $(SCR_DEST_DIR) $(INIT_DEST_DIR) $(CONF_DEST_DIR)); do \
		if ! ls $$d >&/dev/null; then \
			rmdir $$d; \
		fi; \
	done

clean:
	find $(THISMAKEFILEDIR) -name '*~' -delete
	find $(THISMAKEFILEDIR) -name '*.tgz' -delete
	rm -f $(RPMPATHS)
