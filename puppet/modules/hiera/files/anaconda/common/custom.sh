function set_color_prompt() {
    # Color prompt, using some code stolen from Gentoo's
    # /etc/bash/bashrc -- thomlee 2008/08/06

    # Set colorful PS1 only on colorful terminals.

    # dircolors --print-database uses its own built-in database
    # instead of using /etc/DIR_COLORS.  Try to use the external file
    # first to take advantage of user additions.  Use internal bash
    # globbing instead of external grep binary.

    # Do nothing if we're not an interactive shell
    if [ ! "$PS1" ]; then
	return
    fi

    local use_color= match_lhs=
    local safe_term=${TERM//[^[:alnum:]]/?}   # sanitize TERM
    if [[ -f /etc/DIR_COLORS ]] ; then
	match_lhs=$(</etc/DIR_COLORS)
    elif type -p dircolors >/dev/null ; then
	match_lhs=$(dircolors --print-database)
    else
	match_lhs=""
    fi
    [[ $'\n'${match_lhs} == *$'\n'"TERM "${safe_term}* ]] && use_color=true

    # This stuff should make things a bit more user-friendly -- thomlee
    # 2008/08/06

    local csi='\033['
    local cstart="\[${csi}"
    local cend="m\]"
    local reset="${cstart}${cend}"
    local black="${cstart}30${cend}"
    local dred="${cstart}31${cend}"
    local dgreen="${cstart}32${cend}"
    local dyellow="${cstart}33${cend}"
    local dblue="${cstart}34${cend}"
    local dmagenta="${cstart}35${cend}"
    local dcyan="${cstart}36${cend}"
    local lgray="${cstart}37${cend}"
    local dgray="${cstart}01;30${cend}"
    local red="${cstart}01;31${cend}"
    local green="${cstart}01;32${cend}"
    local yellow="${cstart}01;33${cend}"
    local blue="${cstart}01;34${cend}"
    local magenta="${cstart}01;35${cend}"
    local cyan="${cstart}01;36${cend}"
    local white="${cstart}01;37${cend}"

    local date host dir user prompt
    if [ "${use_color}" ]; then
	date=$blue
	host=$magenta
	dir=$cyan
	if [[ ${EUID} == 0 ]] ; then
	    user=$red   # The idea here is WARNING!  YOU ARE ROOT!  BE CAREFUL!
	    prompt=$red
	else
	    user=$green
	    prompt=$green
	fi
	alias ls='ls --color=auto'
	alias grep='grep --colour=auto'
    fi
    PS1="[\$?] $date\D{%T %Z}$reset [$user\u$reset@$host\h$reset:$dir\W$reset]$prompt\\\$$reset "
}

set_color_prompt
unset set_color_prompt

pathmunge () {
    case ":${PATH}:" in
        *:"$1":*)
            ;;
        *)
            if [ "$2" = "after" ] ; then
                PATH=$PATH:$1
            else
                PATH=$1:$PATH
            fi
    esac
}

pathmunge /opt/bin
if [ "$EUID" = "0" ]; then
    pathmunge /opt/sbin
else
    pathmunge /opt/sbin after
fi
unset pathmunge

# Deal with the fact that there are systems with a different umask (one of the
# devs requested long ago that we have a non-default umask of 022 everywhere,
# instead of the distro's default policy of 022 for system accounts and 002 for
# user accounts, but this interferes with some services, so we had to make
# exceptions) without customizing this file. If /opt/etc/umask exists, source
# it and do whatever it does. If it doesn't exist, use the "GOC default" umask
# 022. If you want the RHEL/CentOS default (022 system, 002 user), make an
# empty /opt/etc/umask; then the default setting in /etc/profile won't be
# overridden. If you want a fixed umask other than 022 for all users, make
# /opt/etc/umask and put 'umask XXX' in it.
if [[ -e /opt/etc/umask ]]; then
    . /opt/etc/umask
else
    umask 022
fi

if [[ -z $SUDO_UID ]]; then
    alias ssu='sudo -Hi su'
fi

function x509test() {
    #
    # x509test <cert> <key> will tell you whether a cert and key are compatible
    #
    local string="Hello World"
    local result=$(echo "$string" | openssl smime -encrypt $1 | openssl smime -decrypt -inkey $2)
    result="${result/[$'\n\r']/}"
    if [[ $result == $string ]]; then
	echo "Success"
	return 0
    else
	echo "Failed ($result)"
	return 1
    fi
}

function x509less() {
    #
    # x509less <cert> will print a cert to the screen, paged with less
    #
    openssl x509 -noout -text -in $1 | less
}
