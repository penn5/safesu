#!/system/bin/sh

exec 0<&- # close stdin ready for the remote sh process
rpipe=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 50)
/system/etc/nomagic/busybox mknod /system/etc/nomagic/sureq/$pipe p # the inotify will see this pipe and launch a handler.
wpipe=/system/etc/nomagic/sus/$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 50)
/system/etc/nomagic/busybox mknod $pipe p # the inotify will not see this pipe because its in sus not sureq.
echo "$rpipe" >> $wpipe
read -r hello < $rpipe
[ "$hello" = "hello" ] || (echo "didnt get hello!";exit 1)
echo "$(tty | cut -d / -f 4)" >> $wpipe # tell the su_hander where to send the su process. This **could** be abused to grant root to another app but that is possible even if you use a normal kind of su
read -r message < $rpipe
[ "$message" = "ok" ] || (echo "didnt get okay!";exit 1)


#dd if=$stdout of=/dev/stdout &
#dd if=$stderr of=/dev/stderr &
#dd if=/dev/stdin of=$stdin
