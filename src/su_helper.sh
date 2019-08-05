#!/system/bin/sh
# Just launch su_handler in background with no stdio to avoid errors and deadlocks
# TODO: redirect output to a log file somewhere
/system/etc/nomagic/su_handler >/dev/null 2>&1 & disown
