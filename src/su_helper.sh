#!/system/bin/sh
# Just launch su_handler in background with no stdio to avoid errors and deadlocks
# TODO: redirect output to a log file somewhere

DIR="$(realpath "$(dirname "$(readlink -f "$0")")")"

nohup "$DIR/su_handler.sh" >>/data/adb/root.log 2>&1 </dev/null &
