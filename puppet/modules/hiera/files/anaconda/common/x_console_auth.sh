# Merge the X11 authority of whomever owns the tty, if any, which will allow
# that user to run X programs on their console.  I wish su did this
# automatically. -- TJL 2011/10/06
TTY=`tty`
if [ "${TTY#/dev}" != "$TTY" ]; then
  CONSOLE_OWNER=`stat -c '%U' "$TTY"`
  if [ "$CONSOLE_OWNER" != "$USER" ]; then
    CONSOLE_OWNER_HOME=`getent passwd "$CONSOLE_OWNER" | cut -d : -f 6`
    X_AUTH_FILE="$CONSOLE_OWNER_HOME/.Xauthority"
    if [ -e "$X_AUTH_FILE" ]; then
      xauth merge "$X_AUTH_FILE"
    fi
  fi
fi

unset TTY CONSOLE_OWNER CONSOLE_OWNER_HOME X_AUTH_FILE
