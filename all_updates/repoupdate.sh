#!/bin/bash

# repoupdate -- update the local YUM repo mirrors
# Tom Lee <thomlee@iu.edu>
# Begun 2015-11-30
# This version: 2016-06-20

# Used to always do this by hand, sometimes going back in shell
# history to find the commands -- decided it was time to put it in a
# script so none of that would be lost.

# Where the RPMs are for different distros:

# RHEL 5:
# epel-x86_64-5 just has the RPMs in it directly
# rhel-x86_64-server*-5 have getPackage directories with the RPMs

# RHEL 6:
# epel-x86_64-6 just has the RPMs in it directly
# rhel-x86_64-server*-6 have getPackage directories with the RPMs

# CentOS 6:
# no epel directory; uses RHEL 6 epel
# centos-x86_64*-6 have Packages directories with the RPMs

# CentOS 7:
# epel-x86_64-7 has one-character directories containing RPMs starting
#   with that character
# centos-x86_64*-7 have Packages directories with the RPMs

# In all cases the repodata dir (created by the createrepo command and
# necessary for it to function as a repo) is in the top-level repo dir
# (e.g. epel-x86_64-5)

COBBLER_DIR=/usr/local/cobbler
COBBLER_REPO_MIRROR_DIR=$COBBLER_DIR/repo_mirror

function print_help() {
    # Print some helpful messages.

    cat <<EOF > /dev/stderr
Usage: $0 [options]
Options:
  -d: Print debug text
  -h: This help message
  -l: Skip repomanage limiting step
  -s: Skip reposync syncing step
  -t: Test mode: print commands that would be executed without executing them
EOF
}

function handle_options() {
    # Handle the command-line options.  The getopts command (a bash builtin)
    # returns true as long as the positional parameters contain more
    # constructions that look like command-line options.  It places the index
    # of the current option in $OPTIND and the argument (if there is one) of
    # the current option in $OPTARG.  The arguments of getopts itself are a
    # string consisting of the options it's supposed to recognize and the
    # variable to put the recognized option into.  Now, getopts stops when it
    # reaches a "--", which is intentional, to allow script writers to make it
    # possible to pass options on to other programs the script calls, and
    # that's what we're doing here -- anything after a "--" is to be passed on
    # to yum.  This function, after getopts hits a "--", cuts it and everything
    # before it from $@ and saves what's left in $YUM_OPTS.  This doesn't
    # affect the global command-line parameters; it only operates on the
    # positional parameters passed to the function (which is why the
    # command-line parameters have to be passed to it).

    local opt
    while getopts "dhlst" opt; do
	case "$opt" in
	    d)
		DEBUG=1
		echo "DEBUG mode on due to -d option.  You will see DEBUG messages." > /dev/stderr
		;;
	    h)
		print_help
		exit 0
		;;
	    l)
		SKIPLIMIT=1
		;;
	    s)
		SKIPSYNC=1
		;;
	    t)
		TEST=1
		echo "TEST mode on due to -t option.  Update will be simulated." > /dev/stderr
		;;
	    ?)
		echo "Error: Required parameter missing" > /dev/stderr
		print_help
		exit 1
		;;
	    *)
		echo "Error: Unknown option" > /dev/stderr
		print_help
		exit 1
		;;
	esac
    done
    shift $(( $OPTIND - 1 ))
    REMAINING_OPTS="$@"
}

function debug_echo() {
    # Print the given string, but only if $DEBUG is set.
    local msg="$1"
    if [[ $DEBUG ]]; then
	echo "(DEBUG) $msg"
    fi
}

function dangerous_command() {
    # For system-affecting commands, when you want to test them before
    # you run them.  If $TEST is set, print the given command.  If
    # not, execute it.
    local cmd="$1"
    if [[ $TEST ]]; then
	echo "(TEST MODE) $cmd"
    else
	eval "$cmd"
    fi
}

function cobbler_reposync() {
    # Actually update the repos with the latest packages
    dangerous_command "cobbler reposync --tries=5"
}

function trim_repos() {
    # Use repomanage to make sure we don't keep older versions of the
    # files forever -- keep only the most recent 3 versions of
    # everything.

    local repodir rpmdir

    pushd $COBBLER_REPO_MIRROR_DIR >/dev/null
    # Search through top-level directories for directories containing
    # a "repodata" subdirectory; those will be repo directories
    for repodir in $(find . -maxdepth 1 -type d | sort); do
	if [[ -d "$repodir/repodata" ]]; then
	    pushd $repodir >/dev/null
	    # Find all directories that contain at least one .rpm file
	    for rpmdir in $(find . -type d | sort); do
		if [[ -n $(find $rpmdir -maxdepth 1 -type f -name '*.rpm' -print -quit) ]]; then
		    # $rpmdir contains at least one .rpm file -- this will
		    # be a path relative to $repodir and will be '.' if
		    # $repodir itself contains any .rpm files.
		    echo "Limiting size of $repodir/$rpmdir ..."
		    dangerous_command "repomanage -k 3 -o $rpmdir | xargs rm -f"
		fi
	    done
	    echo "Rebuilding metadata for $repodir ..."
	    dangerous_command "createrepo -c cache --update ."
	    popd >/dev/null
	fi
    done
    popd >/dev/null
}

handle_options "$@"
if [[ $SKIPSYNC ]]; then
    echo "Skipping sync step due to -s option."
else
    cobbler_reposync
fi
if [[ $SKIPLIMIT ]]; then
    echo "Skipping limit step due to -l option."
else
    trim_repos
fi
