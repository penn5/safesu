#!/system/bin/sh
# busybox that we use says:
#/*
# * Use as follows:
# * # inotifyd /user/space/agent dir/or/file/being/watched[:mask] ...
# *
# * When a filesystem event matching the specified mask is occured on specified file (or directory)
# * a userspace agent is spawned and given the following parameters:
# * $1. actual event(s)
# * $2. file (or directory) name
# * $3. name of subfile (if any), in case of watching a directory
# *
# * E.g. inotifyd ./dev-watcher /dev:n
# *
# * ./dev-watcher can be, say:
# * #!/bin/sh
# * echo "We have new device in here! Hello, $3!"
# *
# * See below for mask names explanation.
# */
# We are ./dev-watcher in the above example.

# The mask is :n so we know we will not have to check the type.

find_package_name () {
	if [ "$1" = "1" ]; then
		return 1
	fi
	exe=$(readlink "/proc/$1/exe")
	if [ "$exe" = "/system/bin/app_process" -o "$exe" = "/system/bin/app_process32" -o "$exe" = "/system/bin/app_process64" ]; then
		# Its the one we're looking for
		package=$(cat "/proc/$1/cmdline")
		return 0
	else
		return find_package_name $(cat "/proc/$1/status" | grep '^Ppid:' | cut -d '\t' -f 2)
	fi
}

echo "$1 $2 $3"

rpipe="/system/etc/nomagic/sureq/$3"

if [ ! -p $rpipe ]; then
	echo "$p not a pipe"
	exit 0 #probably just some naughty person trying to trick is, we don't care.
fi



# Make sure this process is allowed su access before we even set up the write channel.
read -r pidverif < "$rpipe"
echo "$pidverif" | grep '[^a-zA-Z0-9]'
if [ "$?" = "0" ]; then
	echo "INVALID PIDVERIF"
	exit 40
fi

pidverif="/system/etc/nomagic/pidverif/$pidverif"
if [ ! -f "$pidverif" ]; then
	echo "INVALID PIDVERIF"
	exit 40
fi

read -r pidcheck < "$pidverif"
read -r wpipe < "$rpipe"

if [ ! "$rpipe" = "$pidcheck" ]; then
	echo "SECURITY ERROR, ABORTING BEFORE WE ARE DETECTED!"
	exit 99
fi

openpid=$(lsof -t "$pidverif" | cut -d , -f 1)
if [ -z "$openpid" ]; then
	echo "NOONE HAS OPENED THE SECURITY CHECK FILE, UNABLE TO VERIFY PID."
	exit 97
fi
find_package_name $openpid
if [ -z "$package" ]; then
	pkgname="$(cat /proc/$openpid/cmdline)"
else
	pkgname="$package"
fi
echo "Processing root request from package/process: $pkgname"
grep "^$pkgname$" /data/adb/rootallow.txt ||  { echo "SECURITY ERROR, UNAUTHORIZED SU REQUEST. EXITING. "; exit 98; }

# Assert that wpipe is alphanumerical and the right length, otherwise we might get someone trying to abuse the su daemon to write to arbritary locations on disk as root, potentially /data/adb/rootallow.txt.
echo "$wpipe" | grep '[^a-zA-Z0-9]'
if [ "$?" = "0" ]; then
	echo "INVALID WPIPE"
	exit 1
fi

wpipe="/system/etc/nomagic/sus/$wpipe"

if [ ! -p "$wpipe" ]; then
	echo "WPIPE DOES NOT EXIST"
	exit 2
fi
echo "0" >> "$wpipe"

read -r tty < "$rpipe"

# We sanitize this too
# Since /dev/tty* is only accesible to hardware stuff that we don't care about, we can assume we should look in /dev/pts/ for the terminal. Hence, lets sanitize that the input must purely numerical.
if [ -z "$tty" ]; then
	interactive=0
else
	echo "$tty" | grep '[^0-9]'
	if [ "$?" = "0" ]; then
		echo "okn't" >> "$wpipe"
		echo "INVALID TTY: $tty"
		exit 3
	fi

	tty="/dev/pts/$tty"
	if [ ! -e "$tty" ]; then
		echo "okn't" >> "$wpipe"
		echo "TTY DOES NOT EXIST: $tty"
		exit 4
	fi
	interactive=1
fi
echo "ok" >> "$wpipe"

read -r mountns < "$rpipe"

echo "$mountns" | grep '[^0-9]'
if [ "$?" = "0" -o -z "$mountns" ]; then
	echo "okn't" >> "$wpipe"
	echo "INVALID MOUNT MODE: $mountmode"
	exit 5
fi
echo "ok" >> "$wpipe"

echo reading shell
read -r shell < "$rpipe"
echo "read shell"

# Don't need to sanitize, it is meant to be executable. lets just make sure to quote it and do a sanity check.
if [ -z "$shell" ]; then
	echo "okn't" >> "$wpipe"
	echo "INVALID SHELL: $shell"
	exit 6
fi
echo "ok" >> "$wpipe"

read -r userenv < "$rpipe"
# A username can be almost anything, so again, quote and sanity
echo "ok" >> "$wpipe"

#the username should override the stuff in the generic environment, so lets do that first.

read -r environ < "$rpipe"
if [ ! -z environ ]; then
	while IFS= read -r -d '' envvar ; do
		envname="$(cut -d '=' -f 1)"
		envval="$(cut -d '=' -f 2)"
		export "$envname"="$envval" # I tested this, it works, surprisingly! lol
	done <<< "$environ"
fi
echo "ok" >> "$wpipe"

if [ ! -z "$userenv" ]; then
	# Now we can finally set the user variables.
	export USER="$userenv"
	export LOGNAME="$userenv"
else
	export USER="root"
	export LOGNAME="root"
fi

read -r command < "$rpipe"
echo 0
# Lets start building the command we will later run.
#base and shell:
cmd="/system/etc/nomagic/busybox setsid /system/bin/sh -c '$shell"

if [ ! -z "$command" ]; then
	cmd="$cmd -c \\'$command\\'"
fi
echo 1
#End the command

echo $interactive >> "$wpipe"

if [ "$interactive" = "1" ]; then
	echo 2
	cmd="$cmd <$tty >$tty 2>$tty" #Make $? literal, so its evaluated later, like laaaaaaaater.
else
	echo 3
	stdinpipe=/system/etc/nomagic/sureq/$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 50)
	stdoutpipe=/system/etc/nomagic/sureq/$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 50)
	stderrpipe=/system/etc/nomagic/sureq/$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 50)
	/system/etc/nomagic/busybox mknod "$stdinpipe" p
	/system/etc/nomagic/busybox mknod "$stdoutpipe" p
	/system/etc/nomagic/busybox mknod "$stderrpipe" p
	echo "$stdinpipe" >> "$wpipe"
	echo "$stdoutpipe" >> "$wpipe"
	echo "$stderrpipe" >> "$wpipe"
	cmd="$cmd >$stdoutpipe <$stdinpipe 2>$stderrpipe"
fi

cmd="$cmd; echo "'$?'" >> $wpipe'"

echo "$cmd"

chuid=$(id -ru $USER)
if [ "$mountns" = "0" ]; then
	chnspath=""
else
	chnspath="/proc/$mountns/ns/mnt"
fi
# TODO: check package name and make sure they are allowed root. packagename is in /proc/pid/cmdline
echo 4
echo "ok" >> "$wpipe"
read -r message < "$rpipe"
[ "$message" = "go" ] || { echo "they aborted!"; exit 20; }
/system/etc/nomagic/busybox nsenter -m$chnspath -S$chuid -- /system/bin/sh -c "$cmd"
echo 5

exit 10


