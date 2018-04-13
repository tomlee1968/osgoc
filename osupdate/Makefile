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

# Scripts
SCR_SRC_DIR:=$(THISMAKEFILEDIR)/scripts
SCR_FILES:=osupdate
SCR_DEST_DIR:=$(BUILDROOT)/opt/sbin

SCR_SRC_PATHS:=$(addprefix $(SCR_SRC_DIR)/,$(SCR_FILES))
SCR_DEST_PATHS:=$(addprefix $(SCR_DEST_DIR)/,$(SCR_FILES))

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
	tarball rpm uninstall clean

# Help message
help:
	@echo "Things you can type:"
	@echo "make help: This message"
	@echo "make tarball: Creates tarball"
	@echo "make rpm: Creates RPM"
	@echo "make clean: Removes all but source files"
	@echo "make install-script (requires root): Installs main script"
	@echo "make install (requires root): Same as install-script"
	@echo "make uninstall (requires root): Removes everything installed"

# Installation
install:  install-script

# Directory
$(SCR_DEST_DIR):
	mkdir -p -m0755 $@

# Script
install-script: $(SCR_DEST_DIR) $(SCR_DEST_PATHS)

$(SCR_DEST_PATHS): $(SCR_DEST_DIR)/%: $(SCR_SRC_DIR)/%
	install -m0744 $^ $@

# Tarball
tarball: $(TARBALL_PATH)

$(TARBALL_PATH): /tmp/$(TARBALL)
	@mv /tmp/$(TARBALL) $(THISMAKEFILEDIR)

/tmp/$(TARBALL):
	@echo "*** Creating $(TARBALL_PATH) ..."
	@TEMPDIR=$(shell mktemp -d /tmp/$(PACKAGE)make.XXXXXXXXXX); \
		cd $$TEMPDIR; \
		cp -a $(THISMAKEFILEDIR) $(PV); \
		tar zcf /tmp/$(TARBALL) --exclude "*.tgz" --exclude ".svn" --exclude "*~" $(PV); \
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
uninstall: $(SCR_DEST_PATHS) $(SCR_DEST_DIR)
	rm -f $(SCR_DEST_PATHS)
	if ! ls $(SCR_DEST_DIR); then \
		rmdir $(SCR_DEST_DIR); \
	fi

clean:
	find $(THISMAKEFILEDIR) -name '*~' -delete
	find $(THISMAKEFILEDIR) -name '*.tgz' -delete
	rm -f $(RPMPATHS)
