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
SCR_FILES:=tuitility
SCR_DEST_DIR:=$(BUILDROOT)/opt/sbin

SCR_SRC_PATHS:=$(addprefix $(SCR_SRC_DIR)/,$(SCR_FILES))
SCR_DEST_PATHS:=$(addprefix $(SCR_DEST_DIR)/,$(SCR_FILES))

# The module(s)
MOD_SRC_DIR:=$(THISMAKEFILEDIR)/plugins
MOD_FILES:=$(shell ls $(MOD_SRC_DIR))
MOD_DEST_DIR:=$(BUILDROOT)/usr/local/share/perl5/TUItility/Mode

MOD_SRC_PATHS:=$(addprefix $(MOD_SRC_DIR)/,$(MOD_FILES))
MOD_DEST_PATHS:=$(addprefix $(MOD_DEST_DIR)/,$(MOD_FILES))

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
	install-script \
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
	@echo "make install (requires root): Installs everything"
	@echo "make uninstall (requires root): Removes everything installed"

$(sort $(SCR_DEST_DIR) $(MOD_DEST_DIR)):
	mkdir -p -m0755 $@

# Installation
install: install-script install-mods

# Script installation
install-script: $(SCR_DEST_DIR) $(SCR_DEST_PATHS)

$(SCR_DEST_PATHS): $(SCR_DEST_DIR)/%: $(SCR_SRC_DIR)/%
	install -m0755 $^ $@

# Module installation
install-mods: $(MOD_DEST_DIR) $(MOD_DEST_PATHS)

$(MOD_DEST_PATHS): $(MOD_DEST_DIR)/%: $(MOD_SRC_DIR)/%
	install -m0644 $^ $@

# Tarball
tarball: $(TARBALL_PATH)

$(TARBALL_PATH): /tmp/$(TARBALL)
	@mv /tmp/$(TARBALL) .

/tmp/$(TARBALL): $(SCR_SRC_PATHS) $(MOD_SRC_PATHS) $(THISMAKEFILEPATH) $(SPEC)
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
uninstall: $(SCR_DEST_PATHS) $(MOD_DEST_PATHS)
	rm -f $(SCR_DEST_PATHS) $(MOD_DEST_PATHS)
	for d in $(sort $(SCR_DEST_DIR) $(MOD_DEST_DIR)); do \
		if ! ls $$d >&/dev/null; then \
			rmdir $$d; \
		fi; \
	done

clean:
	find $(THISMAKEFILEDIR) -name '*~' -delete
	find $(THISMAKEFILEDIR) -name '*.tgz' -delete
	rm -f $(RPMPATHS)
