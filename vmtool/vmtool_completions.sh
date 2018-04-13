# Completions for vmtool

function _autovm() {
    local cur=${COMP_WORDS[$COMP_CWORD]}
    local args='-d -h -t -v'
    local vms=$(lsvm | cut -d ' ' -f 1)
    COMPREPLY=( $(compgen -W "$args $vms" -- $cur) )
    return 0
}

complete -r autovm >&/dev/null
complete -F _autovm autovm

function _exportvm() {
    local cur=${COMP_WORDS[$COMP_CWORD]}
    # Determine whether we're looking for a parameter for the previous arg or
    # whether we're clear of all that
    local prev=${COMP_WORDS[$COMP_CWORD-1]}
    local args='-c -d -f -h -s -t -v'
    local vms=$(lsvm | cut -d ' ' -f 1)
    case "$prev" in
	-f)
	    COMPREPLY=( $(compgen -f -o filenames -- $cur) )
	    ;;
	*)
	    COMPREPLY=( $(compgen -W "$args $vms" -- $cur) )
	    ;;
    esac
    return 0
}

complete -r exportvm >&/dev/null
complete -F _exportvm exportvm

function _importvm() {
    local cur=${COMP_WORDS[$COMP_CWORD]}
    # Determine whether we're looking for a parameter for the previous arg or
    # whether we're clear of all that
    local prev=${COMP_WORDS[$COMP_CWORD-1]}
    local args='-d -h -n -t -v'
    case "$prev" in
	-n)
	    COMPREPLY=()
	    ;;
	*)
	    COMPREPLY=( $(compgen -f -o filenames -W "$args" -- $cur) )
	    ;;
    esac
    return 0
}

complete -r importvm >&/dev/null
complete -F _importvm importvm

function _mkvm() {
    local cur=${COMP_WORDS[$COMP_CWORD]}
    # Determine whether we're looking for a parameter for the previous arg or
    # whether we're clear of all that
    local prev=${COMP_WORDS[$COMP_CWORD-1]}
    local args='-3 -a -c -d -f -h -i -m -n -p -r -s -t -v'
    case "$prev" in
	-c)
	    COMPREPLY=()
	    ;;
	-f)
	    COMPREPLY=( $(compgen -f -o filenames -- $cur) )
	    ;;
	-m)
	    COMPREPLY=()
	    ;;
	-r)
	    COMPREPLY=( $(compgen -W '6 c6 c7 5' -- $cur) )
	    ;;
	-s)
	    COMPREPLY=()
	    ;;
	*)
	    COMPREPLY=( $(compgen -W "$args" -- $cur) )
	    ;;
    esac
    return 0
}

complete -r mkvm >&/dev/null
complete -F _mkvm mkvm

function _noautovm() {
    local cur=${COMP_WORDS[$COMP_CWORD]}
    local args='-d -h -t -v'
    local vms=$(lsvm | cut -d ' ' -f 1)
    COMPREPLY=( $(compgen -W "$args $vms" -- $cur) )
    return 0
}

complete -r noautovm >&/dev/null
complete -F _noautovm noautovm

function _rebuild_stemcell() {
    local cur=${COMP_WORDS[$COMP_CWORD]}
    # Determine whether we're looking for a parameter for the previous arg or
    # whether we're clear of all that
    local prev=${COMP_WORDS[$COMP_CWORD-1]}
    local args='-3 -d -f -h -r -t -v -x'
    case "$prev" in
	-f)
	    COMPREPLY=( $(compgen -f -o filenames -- $cur) )
	    ;;
	-r)
	    COMPREPLY=( $(compgen -W '6 c6 c7 5' -- $cur) )
	    ;;
	*)
	    COMPREPLY=( $(compgen -W "$args" -- $cur) )
	    ;;
    esac
    return 0
}

complete -r rebuild_stemcell >&/dev/null
complete -F _rebuild_stemcell rebuild_stemcell

function _rmvm() {
    local cur=${COMP_WORDS[$COMP_CWORD]}
    local args='-d -h -t -v'
    local vms=$(lsvm | cut -d ' ' -f 1)
    COMPREPLY=( $(compgen -W "$args $vms" -- $cur) )
    return 0
}

complete -r rmvm >&/dev/null
complete -F _rmvm rmvm

function _swapvm() {
    local cur=${COMP_WORDS[$COMP_CWORD]}
    local args='-d -h -t -v'
    local vms=$(lsvm | cut -d ' ' -f 1)
    COMPREPLY=( $(compgen -W "$args $vms" -- $cur) )
    return 0
}

complete -r swapvm >&/dev/null
complete -F _swapvm swapvm

function _vmup() {
    local cur=${COMP_WORDS[$COMP_CWORD]}
    local args='-d -h -t -v'
    local vms=$(lsvm | cut -d ' ' -f 1)
    COMPREPLY=( $(compgen -W "$args $vms" -- $cur) )
    return 0
}

complete -r vmup >&/dev/null
complete -F _vmup vmup

function _vmdown() {
    local cur=${COMP_WORDS[$COMP_CWORD]}
    local args='-d -h -t -v'
    local vms=$(lsvm | cut -d ' ' -f 1)
    COMPREPLY=( $(compgen -W "$args $vms" -- $cur) )
    return 0
}

complete -r vmdown >&/dev/null
complete -F _vmdown vmdown
