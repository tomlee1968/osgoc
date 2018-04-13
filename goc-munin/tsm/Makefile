###############################################################################
# Variables
###############################################################################

# Package and version
CWD=$(shell /bin/pwd)
CWD_BASE=$(notdir $(CWD))
PACKAGE=munin_$(CWD_BASE)
SPEC=$(PACKAGE).spec
VERSION=$(shell grep "^Version: " $(SPEC) | sed -e "s/^Version: *//")
PACK_VERS=$(PACKAGE)-$(VERSION)

# Files
PLUGINS=tsm
CONFIGS=

# Where files come from
PLUGIN_SRC=plugins
CONFIG_SRC=config

# Where files go to
PLUGIN_DIR=$(ROOT)/opt/share/munin/plugins
SYMLINK_DIR=$(ROOT)/etc/munin/plugins
CONFIG_DIR=$(ROOT)/etc/munin/plugin-conf.d

# Relative path from $(SYMLINK_DIR) to $(PLUGIN_DIR)
REL_PATH=../../../opt/share/munin/plugins

# Combined paths
PLUGIN_PATHS=$(addprefix $(PLUGIN_DIR)/,$(PLUGINS))
SYMLINK_PATHS=$(addprefix $(SYMLINK_DIR)/,$(PLUGINS))
CONFIG_PATHS=$(addprefix $(CONFIG_DIR)/,$(CONFIGS))

# Binary locations
CP=/bin/cp
FIND=/usr/bin/find
INSTALL=/usr/bin/install -bDp
LN=/bin/ln
MKTEMP=/bin/mktemp
MV=/bin/mv
RPMBUILD=/usr/bin/rpmbuild
TAR=/bin/tar

# Tarball
TARBALL=$(PACK_VERS).tgz

# RPM
RPMBD=$(HOME)/rpmbuild

###############################################################################
# Rules
###############################################################################

.PHONY=install install_plugin install_symlink install_config \
	tarball rpm uninstall clean

install: install_plugin install_symlink install_config

# Plugin

install_plugin: $(PLUGIN_PATHS)

$(PLUGIN_PATHS): $(PLUGIN_DIR)/%: $(PLUGIN_SRC)/%
	$(INSTALL) -m0744 $< $@

# Symlink

#install_symlink: $(SYMLINK_DIR)/tsm
install_symlink: $(SYMLINK_PATHS)

#$(SYMLINK_DIR)/tsm:
#	$(INSTALL) -d -m0755 $(SYMLINK_DIR)
#	cd $(SYMLINK_DIR); $(LN) -s ../../../opt/share/munin/plugins/tsm tsm

$(SYMLINK_PATHS): $(SYMLINK_DIR)/%: $(PLUGIN_DIR)/%
	if [ ! -d "$(SYMLINK_DIR)" ]; then if [ -e "$(SYMLINK_DIR)" ]; then mv "$(SYMLINK_DIR)" "$(SYMLINK_DIR).bak"; fi; $(INSTALL) -d -m0755 $(SYMLINK_DIR); fi
	$(LN) -s $(REL_PATH)/$(notdir $<) $@

# Config

install_config: $(CONFIG_PATHS)

$(CONFIG_PATHS): $(CONFIG_DIR)/%: $(CONFIG_SRC)/%
	$(INSTALL) -m0644 $< $@

# Tarball

tarball: $(TARBALL)

$(TARBALL): /tmp/$(TARBALL)
	$(MV) /tmp/$(TARBALL) .

/tmp/$(TARBALL): 
/tmp/$(TARBALL):
	TEMPDIR=$(shell $(MKTEMP) -d /tmp/$(PACKAGE)make.XXXXXXXXXX); \
		cd ..; \
		$(CP) -a $(CWD_BASE) $$TEMPDIR/$(PACK_VERS); \
		$(TAR) zcvf /tmp/$(TARBALL) -C $$TEMPDIR --exclude $(PACK_VERS)/$(PACKAGE)-*.tgz $(PACK_VERS); \
		$(RM) -rf $$TEMPDIR

# RPM

rpm: tarball
	$(CP) -p $(TARBALL) $(RPMBD)/SOURCES
	$(RPMBUILD) -ba $(PACKAGE).spec

# Utility

uninstall:
	$(RM) $(PLUGIN_PATHS) $(SYMLINK_PATHS) $(CONFIG_PATHS)

clean:
	$(FIND) . -name '*~' -exec $(RM) {} \;
	$(RM) $(TARBALL)
