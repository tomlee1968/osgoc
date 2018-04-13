function print_login_warning() {
    # A warning message if we're logged in as root

    local csi='\033['
    local cstart="${csi}"
    local cend="m"
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
    local normal='00'
    local bold='01'
    local negative='07'
    local prim='10'
    local alt1='11'
    local alt2='12'
    local alt3='13'
    local alt4='14'
    local alt5='15'
    local alt6='16'
    local alt7='17'
    local alt8='18'
    local alt9='19'
    local fg_black='30'
    local fg_red='31'
    local fg_green='32'
    local fg_yellow='33'
    local fg_blue='34'
    local fg_magenta='35'
    local fg_cyan='36'
    local fg_gray='37'
    local fg_default='39'
    local fg_br_white='97'
    local bg_black='40'
    local bg_red='41'
    local bg_green='42'
    local bg_yellow='43'
    local bg_blue='44'
    local bg_magenta='45'
    local bg_cyan='46'
    local bg_gray='47'
    local bg_default='49'

    # Printing colors:
    # ${cstart}<semicolon-separated list of numbers>${cend}

    echo -e "$cstart$bg_red;$fg_gray${cend}┌───────────────────────────────────────────────────────────────────────────── $cstart$normal$cend"
    echo -e "$cstart$bg_red;$fg_gray${cend}│                                                                              $cstart$bg_black$cend $cstart$normal$cend"
    echo -e "$cstart$bg_red;$fg_gray${cend}│   $cstart$fg_br_white${cend}WARNING: You are logged in as root on a production server!  Be careful!    $cstart$bg_black$cend $cstart$normal$cend"
    echo -e "$cstart$bg_red;$fg_gray${cend}│                                                                              $cstart$bg_black$cend $cstart$normal$cend"
    echo -e "$cstart$bg_red${cend}                                                                               $cstart$bg_black$cend $cstart$normal$cend"
    echo -e " $cstart$bg_black$cend                                                                               $cstart$normal$cend"
}

if [ "$EUID" -eq 0 ]; then
    print_login_warning
fi

# Now that we're done with the function, don't leave it in the environment
unset print_login_warning
