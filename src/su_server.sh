# How it works:
# The su binary, when called, creates a randomly named pipe in "$DIR/sureq/RaNd0m_bYt3s_h3Re."
# We watch for files being created in that directory, and when its created, we connect.
# "$DIR/sureq" is chmod 1733 (trwx-wx-wx) so that non-root cannot list it. However we are root, so we can list it.
# When we see an incoming connection, we open it and use lsof to check what other processes have a handle on it. If the other process is on the whitelist, we allow it and grant su (NI)

DIR="$(dirname "$(readlink -f "$0")")"

mkdir "$DIR/sus" 2>/dev/null
chmod 1733 "$DIR/sus"
chcon -Rh u:object_r:sdcardfs:s0 "$DIR/sus"

mkdir "$DIR/sureq" 2>/dev/null
chmod 1733 "$DIR/sureq"
chcon -Rh u:object_r:sdcardfs:s0 "$DIR/sureq"

mkdir "$DIR/pidverif" 2>/dev/null
chmod 1733 "$DIR/pidverif"
chcon -Rh u:object_r:sdcardfs:s0 "$DIR/pidverif"

mkdir "$DIR/cmds" 2>/dev/null
chmod 1733 "$DIR/cmds"
chcon -Rh u:object_r:sdcardfs:s0 "$DIR/cmds"

"$DIR/busybox" inotifyd "$DIR/su_helper.sh" "$DIR/sureq:n"
return 1
