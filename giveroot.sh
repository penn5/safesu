#!/system/bin/sh

zygoteMntNs="$(readlink -f /proc/$(pidof zygote)/ns/mnt)"
zygote64MntNs="$(readlink -f /proc/$(pidof zygote64)/ns/mnt)"

logcat -b events -v raw -s am_proc_bound:I | while read line; do
	pid="$(echo $line | cut -d , -f 2)"
	pkgname="$(echo $line | cut -d , -f 4 | cut -d : -f 1)" #e.g. com.brave.browser:sandboxed_process7 needs the :sandboxed_process7 removing, hence the second cut.
	echo "Giving root to pid $pid, package name $pkgname now."
	if [ "$(readlink /proc/$pid/ns/mnt)" == "$zygoteMntNs" -o "$(readlink /proc/$pid/ns/mnt)" == "$zygote64MntNs" ];then
	        echo "$pid, $pkgname didnt change namespace. Cant give su without comprimising system integrity."
	        continue
	fi
	busybox_phh nsenter -m/proc/$pid/ns/mnt -- mount -o bind,private /system/etc/nomagic /system/xbin
	echo "nsenter mount command returned $?"
done
return 2
