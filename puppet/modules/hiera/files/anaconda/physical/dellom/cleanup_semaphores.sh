#!/bin/bash

# cleanup_semaphores.sh -- clean up unused SYSV IPC semaphore sets
# Tom Lee <thomlee@iu.edu>

# Dell OpenManage currently (2011/10/28) leaves behind voluminous numbers of
# semaphore sets by sloppily not removing them when its processes exit.  This
# fills up the system's semaphore set limit and causes errors, and prevents
# other processes from using semaphores, including some that we rely on for
# critical services.  This script deletes semaphore sets that aren't associated
# with any running process.

# For each semaphore set ID
for id in `ipcs -s | sed '1,3d;/^$/d' | cut -d ' ' -f 2`; do
    # This gets the PID of the process that supposedly owns the semaphore set
    p=`ipcs -sp -i $id | tail -n 2 | head -n 1 | sed -re 's/ +/ /g' -e 's/ $//' | cut -d ' ' -f 5`
    # See if that process exists
    if ! ps $p >& /dev/null; then
	# It doesn't; delete the semaphore set
	ipcrm -s $id
    fi
done
