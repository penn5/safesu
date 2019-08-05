#!/system/bin/sh
# Just launch su_handler in background with no stdio to avoid errors and deadlocks
# TODO: redirect output to a log file somewhere
nohup /system/etc/nomagic/su_handler.sh >/data/adb/root.log 2>&1 </dev/null &
