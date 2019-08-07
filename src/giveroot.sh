#!/system/bin/sh

DIR="$(realpath "$(dirname "$(readlink -f "$0")")")"

zygoteMntNs="$(readlink /proc/$(pidof zygote)/ns/mnt)"
zygote64MntNs="$(readlink /proc/$(pidof zygote64)/ns/mnt)"

logcat -b events -v raw -s am_proc_bound | while read -r line
do
#	echo "$line"
	pid="$(echo \"$line\" | cut -d , -f 2)"
	pkgname="$(echo \"$line\" | cut -d , -f 3 | cut -d : -f 1 | sed 's/]\"$//')" #e.g. com.brave.browser:sandboxed_process7 needs the :sandboxed_process7 removing, hence the second cut.
	grep "^$pkgname$" /data/adb/rootallow.txt || continue # Make sure this process is allowed to access root.
	if [ "$(readlink /proc/$pid/ns/mnt)" == "$zygoteMntNs" -o "$(readlink /proc/$pid/ns/mnt)" == "$zygote64MntNs" ];then
	        echo "$pid, $pkgname didnt change namespace. Cant give su without comprimising system integrity."
	        continue
	fi

	echo "Giving root to pid $pid, package name $pkgname now."
	"$DIR/busybox" nsenter -m/proc/$pid/ns/mnt -- mount -t tmpfs none /system/xbin
	echo "nsenter mount command returned $?"
	"$DIR/busybox" nsenter -m/proc/$pid/ns/mnt -- cp "$DIR/busybox" /system/xbin
	echo "nsenter cp command returned $?"
	"$DIR/busybox" nsenter -m/proc/$pid/ns/mnt -- cp "$DIR/su_helper.sh" /system/xbin
	echo "nsenter cp command returned $?"
	"$DIR/busybox" nsenter -m/proc/$pid/ns/mnt -- cp "$DIR/su_handler.sh" /system/xbin
	echo "nsenter cp command returned $?"
	"$DIR/busybox" nsenter -m/proc/$pid/ns/mnt -- cp "$DIR/su_client.sh" /system/xbin/su
	echo "nsenter cp command returned $?"

	"$DIR/busybox" nsenter -m/proc/$pid/ns/mnt -- chcon u:object_r:system_file:s0 "$DIR/busybox"
	echo "nsenter chcon command returned $?"
	"$DIR/busybox" nsenter -m/proc/$pid/ns/mnt -- chcon u:object_r:system_file:s0 "$DIR/su_helper.sh"
	echo "nsenter chcon command returned $?"
	"$DIR/busybox" nsenter -m/proc/$pid/ns/mnt -- chcon u:object_r:system_file:s0 "$DIR/su_handler.sh"
	echo "nsenter chcon command returned $?"
	"$DIR/busybox" nsenter -m/proc/$pid/ns/mnt -- chcon u:object_r:system_file:s0 "$DIR/su"
	echo "nsenter chcon command returned $?"


	"$DIR/busybox" nsenter -m/proc/$pid/ns/mnt -- "$DIR/su_helper.sh"
	echo "nsenter helper command returned $?"
done
return 2
