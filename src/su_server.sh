# How it works:
# The su binary, when called, creates a randomly named pipe in /system/etc/nomagic/sureq/RaNd0m_bYt3s_h3Re.
# We watch for files being created in that directory, and when its created, we connect.
# /system/etc/nomagic/sureq is chmod 1733 (trwx-wx-wx) so that non-root cannot list it. However we are root, so we can list it.
# When we see an incoming connection, we open it and use lsof to check what other processes have a handle on it. If the other process is on the whitelist, we allow it and grant su (NI)

/system/etc/nomagic/busybox inotifyd /system/etc/nomagic/su_handler.sh /system/etc/nomagic/sureq:n
return 0
