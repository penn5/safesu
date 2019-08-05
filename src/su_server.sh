# How it works:
# The su binary, when called, creates a randomly named pipe in /system/etc/nomagic/sureq/RaNd0m_bYt3s_h3Re.
# We watch for files being created in that directory, and when its created, we connect.
# /system/etc/nomagic/sureq is chmod 1733 (trwx-wx-wx) so that non-root cannot list it. However we are root, so we can list it.
# When we see an incoming connection, we open it and use lsof to check what other processes have a handle on it. If the other process is on the whitelist, we allow it and grant su (NI)

mkdir /system/etc/nomagic/sus 2>&1
chmod 1733 /system/etc/nomagic/sus
mkdir /system/etc/nomagic/sureq 2>&1
chmod 1733 /system/etc/nomagic/sureq
mkdir /system/etc/nomagic/pidverif 2>&1
chmod 1733 /system/etc/nomagic/pidverif
mkdir /system/etc/nomagic/cmds 2>&1
chmod 1733 /system/etc/nomagic/cmds

/system/etc/nomagic/busybox inotifyd /system/etc/nomagic/su_helper.sh /system/etc/nomagic/sureq:n
return 1
