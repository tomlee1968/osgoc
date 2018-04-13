#!/bin/bash

# Very first step of install process
# Tom Lee <thomlee@iu.edu>
# Begun 2011/08/31
# Last modified 2013/03/22

# Always a good policy to set PATH in any script that runs as root
export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/opt/sbin:/opt/bin:/usr/local/sbin:/usr/local/bin

# What we do here is use SVN (stemcell should be pre-configured to be able to
# use SVN with the RTCS SVN server) to download the top-level install tree and
# run the install script there, which should take things from there.

#INSTALL_HOME=/opt
INSTALL_HOME=/root
INSTALL_SUBDIR=install
INSTALL_DIR=$INSTALL_HOME/$INSTALL_SUBDIR
INSTALL_SCRIPT=install.sh

SVN_BASE=https://osg-svn.rtinfo.indiana.edu
SVN_HOME=$SVN_BASE/goc-internal
SVN_INST=$SVN_HOME/$INSTALL_SUBDIR
SVN_ARGS="-q --non-interactive --trust-server-cert"

pushd $INSTALL_HOME > /dev/null
svn co $SVN_ARGS --depth immediates $SVN_INST
cd $INSTALL_SUBDIR
./$INSTALL_SCRIPT "$@"
popd > /dev/null
