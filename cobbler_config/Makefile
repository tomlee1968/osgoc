###############################################################################
# Cobbler Config Makefile
#
# Instructions:
# 1. On cobbler.grid.iu.edu, check out cobbler_config from SVN
# 2. Make SURE you're on cobbler.grid and type 'make' as root
# 3. Note: This does NOT (yet) create Cobbler profiles/systems
#
# Note: If you add or remove files to/from stemcellize.tgz, be sure to
# change SCIZE_FILES below.
###############################################################################

###############################################################################
# Variables
###############################################################################

# Magic: Directory this Makefile is in
THISFILE:=$(lastword $(MAKEFILE_LIST))
THISPATH:=$(addprefix $(PWD)/,$(THISFILE))
THISDIR:=$(dir $(THISPATH))
SRC:=$(patsubst %/,%,$(THISDIR))

# Utility
TAR_EXCLUDES:=--exclude ".svn" --exclude "*~"

# Template/Config file path
TPL_RELSRC:=templates
TPL_SRC:=$(SRC)/$(TPL_RELSRC)
TPL_DEST:=/var/lib/cobbler/templates
TPL_FILES:=puppet.conf.template rhel5_ldap.conf.template sssd.conf.template
TPL_FILE_PATHS:=$(addprefix $(TPL_SRC)/,$(TPL_FILES))
TPL_FILE_DESTPATHS:=$(addprefix $(TPL_DEST)/,$(TPL_FILES))

# Stemcellize tarball path
SCIZE_RELSRC:=stemcellize
SCIZE_SRC:=$(SRC)/$(SCIZE_RELSRC)
SCIZE_TGZ_DEST:=/usr/local/cobbler/pub
SCIZE_TGZ_FILE:=stemcellize.tgz
SCIZE_TGZ_DESTPATH:=$(SCIZE_TGZ_DEST)/$(SCIZE_TGZ_FILE)

# Files in the stemcellize tarball
SCIZE_FILES:=50-goc-libvirt-remote-access.pkla virsh.sh \
	bash-prompt-screen bash_profile_thomlee bash_prompt_snippet \
	no_empty_cmd_completion.sh x_console_auth.sh protective_aliases.sh \
	bootstrap_server_5.sh \
	incommon_intermediate_bundle.pem \
	install.sh show_install_msg.sh \
	iptables-config ip6tables-config \
	ldap.secret \
	logrotate_munin-node munin-node.conf \
	logwatch_logfiles_iptables.conf logwatch_services_iptables.conf \
	macros.nvra \
	munin-plugin-conf-cpu munin-plugin-conf-df munin-plugin-conf-ip_ \
	munin-plugin-conf-load \
	networks nscd.conf \
	ntp.conf step-tickers \
	osgops_ca.pub \
	setup_munin_cert_age.cron setup_munin_cert_age.sh \
	rsyslog.conf syslog-ng.conf \
	ssh_known_hosts sshd_config \
	stemcell.grid.iu.edu-hostcert.pem stemcell.grid.iu.edu-hostkey.pem \
	stemcell.resolv.conf.iub \
	svn_bundle.p12 svn_servers
SCIZE_FILE_PATHS:=$(addprefix $(SCIZE_SRC)/,$(SCIZE_FILES))

# Tarballs within stemcellize
LKEYS_TGZ_DEST:=$(SCIZE_SRC)
LKEYS_TGZ_FILE:=localkeys.tar.gz
LKEYS_TGZ_DESTPATH:=$(LKEYS_TGZ_DEST)/$(LKEYS_TGZ_FILE)
LKEYS_RELSRC:=localkeys
LKEYS_SRC:=$(SRC)/$(LKEYS_RELSRC)
LKEYS_TMPPATH:=root/.ssh
LKEYS_FILES:=id_goc.dsa id_goc.dsa.pub id_rsync.dsa id_rsync.dsa.pub
LKEYS_FILE_PATHS:=$(addprefix $(LKEYS_SRC)/,$(LKEYS_FILES))

# This tarball is no longer within stemcellize
PKEYS_TGZ_DEST:=/usr/local/cobbler/pub
PKEYS_TGZ_FILE:=puppet_interjection_keys.tgz
PKEYS_TGZ_DESTPATH:=$(PKEYS_TGZ_DEST)/$(PKEYS_TGZ_FILE)
PKEYS_RELSRC:=puppetkeys
PKEYS_SRC:=$(SRC)/$(PKEYS_RELSRC)
PKEYS_TMPPATH:=etc/puppet/ssl
PKEYS_FILES:=certificate_requests/interjection.uits.indiana.edu.pem \
	public_keys/interjection.uits.indiana.edu.pem \
	certs/interjection.uits.indiana.edu.pem \
	certs/ca.pem crl.pem \
	private_keys/interjection.uits.indiana.edu.pem
PKEYS_FILE_PATHS:=$(addprefix $(PKEYS_SRC)/,$(PKEYS_FILES))

#SCIZE_SUB_TGZ_FILES:=$(LKEYS_TGZ_FILE) $(PKEYS_TGZ_FILE)
SCIZE_SUB_TGZ_FILES:=$(LKEYS_TGZ_FILE)
#SCIZE_SUB_TGZ_PATHS:=$(LKEYS_TGZ_DESTPATH) $(PKEYS_TGZ_DESTPATH)
SCIZE_SUB_TGZ_PATHS:=$(LKEYS_TGZ_DESTPATH)

# Dell OMSA tarball path
OMSA_RELSRC:=goc_dell_omsa
OMSA_SRC:=$(SRC)/$(OMSA_RELSRC)
OMSA_TGZ_DEST:=/usr/local/cobbler/pub
OMSA_TGZ_FILE:=goc_dell_omsa.tgz
OMSA_TGZ_DESTPATH:=$(OMSA_TGZ_DEST)/$(OMSA_TGZ_FILE)

# Files in the Dell OMSA tarball
OMSA_FILES:=55-local-dell_om cleanup_semaphores_cron \
	cleanup_semaphores.sh \
	dellom_alertmail dellom_alertmail_init
OMSA_FILE_PATHS:=$(addprefix $(OMSA_SRC)/,$(OMSA_FILES))

# Cobbler kickstart files
KS_RELSRC:=kickstarts
KS_SRC:=$(SRC)/$(KS_RELSRC)
KS_DEST:=/var/lib/cobbler/kickstarts
KS_FILES:=goc_all.ks goc_rhel5.ks goc_rhel6.ks goc_centos6.ks goc_centos7.ks rescue.ks
KS_FILE_PATHS:=$(addprefix $(KS_SRC)/,$(KS_FILES))
KS_FILE_DESTPATHS:=$(addprefix $(KS_DEST)/,$(KS_FILES))

# Cobbler snippet files
SNIP_RELSRC:=snippets
SNIP_SRC:=$(SRC)/$(SNIP_RELSRC)
SNIP_DEST:=/var/lib/cobbler/snippets
SNIP_FILES:=goc_cleanup goc_define_volumes \
	goc_configure_automount \
	goc_final_disable goc_final_enable \
	goc_configure_bash goc_fix_initscripts \
	goc_configure_inputrc goc_fix_libguestfs \
	goc_configure_iptables goc_get_stemcellize \
	goc_configure_kvm goc_hostname_puppet \
	goc_configure_ldap goc_install_chkusrlocal \
	goc_configure_logrotate goc_install_dell_omsa \
	goc_configure_logwatch goc_install_guardrails \
	goc_configure_netfiles \
	goc_configure_nscd \
	goc_configure_nsswitch goc_install_pause \
	goc_configure_ntpd goc_install_root_ssh_keys \
	goc_configure_openldap goc_install_stemcell_certs \
	goc_configure_postfix goc_install_vm_specific_software \
	goc_configure_rootmail goc_interjection_networking \
	goc_configure_rpm goc_interjection_puppet \
	goc_configure_rsyslog goc_osg_repo goc_internal_yum_repos \
	goc_configure_sssd goc_munin_node \
	goc_configure_sudo goc_preamble \
	goc_configure_svn goc_starter_logfiles \
	goc_configure_syslog-ng goc_stemcell_networking \
	goc_configure_usr_local goc_variant_disk_structures \
	goc_create_directories \
	goc_configure_openssh \
	goc_install_ignored \
	goc_services goc_packages \
	goc_network_config goc_pinc \
	goc_functions
SNIP_FILE_PATHS:=$(addprefix $(SNIP_SRC)/,$(SNIP_FILES))
SNIP_FILE_DESTPATHS:=$(addprefix $(SNIP_DEST)/,$(SNIP_FILES))

###############################################################################
# Rules
###############################################################################

.PHONY: install clean uninstall

install: $(SCIZE_TGZ_DESTPATH) $(PKEYS_TGZ_DESTPATH) $(OMSA_TGZ_DESTPATH) $(KS_FILE_DESTPATHS) $(SNIP_FILE_DESTPATHS) $(TPL_FILE_DESTPATHS)

$(SCIZE_TGZ_DESTPATH): $(SCIZE_FILE_PATHS) $(SCIZE_SUB_TGZ_PATHS) $(addprefix $(SCIZE_SRC)/,$(SCIZE_FILES))
	sudo tar zcf $(SCIZE_TGZ_DESTPATH) -C $(SRC) $(TAR_EXCLUDES) $(addprefix $(SCIZE_RELSRC)/,$(SCIZE_FILES) $(SCIZE_SUB_TGZ_FILES))

$(LKEYS_TGZ_DESTPATH): $(LKEYS_FILE_PATHS)
	td=`mktemp -d -p $(SRC) cobbler.XXXXXXXXXX` && \
	mkdir -p $$td/$(LKEYS_TMPPATH) && \
	pushd $(LKEYS_SRC) >/dev/null && \
	cp -p $(LKEYS_FILES) $$td/$(LKEYS_TMPPATH) && \
	pushd $$td/$(LKEYS_TMPPATH) >/dev/null && \
	chmod 0600 * && \
	chmod 0644 *.pub && \
	popd >/dev/null && \
	popd >/dev/null && \
	tar zcf $(LKEYS_TGZ_DESTPATH) -C $$td $(TAR_EXCLUDES) $(addprefix $(LKEYS_TMPPATH)/,$(LKEYS_FILES)) && \
	rm -rf $$td

$(PKEYS_TGZ_DESTPATH): $(PKEYS_FILE_PATHS)
	td=`mktemp -d -p $(SRC) cobbler.XXXXXXXXXX` && \
	mkdir -p $$td/$(PKEYS_TMPPATH) && \
	pushd $(PKEYS_SRC) > /dev/null && \
	cp -p --parents $(PKEYS_FILES) $$td/$(PKEYS_TMPPATH) && \
	popd > /dev/null && \
	sudo tar zcf $(PKEYS_TGZ_DESTPATH) -C $$td $(TAR_EXCLUDES) $(addprefix $(PKEYS_TMPPATH)/,$(PKEYS_FILES)) && \
	rm -rf $$td

$(OMSA_TGZ_DESTPATH): $(OMSA_FILE_PATHS)
	sudo tar zcf $(OMSA_TGZ_DESTPATH) -C $(SRC) $(TAR_EXCLUDES) $(addprefix $(OMSA_RELSRC)/,$(OMSA_FILES))

$(KS_FILE_DESTPATHS): $(KS_DEST)/%: $(KS_SRC)/%
	sudo install -m 0644 $^ $@

$(SNIP_FILE_DESTPATHS): $(SNIP_DEST)/%: $(SNIP_SRC)/%
	sudo install -m 0644 $^ $@

$(TPL_FILE_DESTPATHS): $(TPL_DEST)/%: $(TPL_SRC)/%
	sudo install -m 0644 $^ $@

clean:
	sudo rm -f $(LKEYS_TGZ_DESTPATH) $(PKEYS_TGZ_DESTPATH)

uninstall:
	sudo rm -f $(SCIZE_TGZ_DESTPATH) $(OMSA_TGZ_DESTPATH) $(KS_FILE_DESTPATHS) $(SNIP_FILE_DESTPATHS)
