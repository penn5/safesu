#!/system/bin/sh

# We are invoked as root. It is our job to initialize comm channels, relabel them as ashmem devices and wait for a connection.
# Everything must stay in our local, hidden directory.

echo "HANDLER INIT"

DIR="$(realpath "$(dirname "$(readlink -f "$0")")")"

PROTOCOL_VERSION=1

find_package_name () {
	echo "$1"
	if [ "$1" = "1" ]; then
		return 1
	fi
	echo "readlink \"/proc/$1/exe\""
	exe=$(readlink "/proc/$1/exe")
	echo "$exe"
	if [ "$exe" = "/system/bin/adbd" -o "$exe" = "/sbin/adbd" ]; then
		return 0
	fi
	if [ "$exe" = "/system/bin/app_process" -o "$exe" = "/system/bin/app_process32" -o "$exe" = "/system/bin/app_process64" ]; then
		# Its the one we're looking for
		package=$(cat "/proc/$1/cmdline" | cut -d '' -f 1)
		echo "$package"
		cat "/proc/$1/cmdline"
		grep "^$package$" /data/adb/rootallow.txt
		if [ "$?" = "0" ]; then
			echo "Package $package is authorised, continuing"
			return 0
		else
			return 1
		fi
	else
		ppidt=$(cat "/proc/$1/status" | grep '^PPid:' | cut -d $'\t' -f 2)
		find_package_name "$ppidt"
		return $?
	fi
}

wpipe="$DIR/su_read.pipe"
rpipe="$DIR/su_write.pipe"

"$DIR/busybox" mknod "$wpipe" p
chcon u:object_r:ashmem_device:s0 "$wpipe"
"$DIR/busybox" mknod "$rpipe" p
chcon u:object_r:ashmem_device:s0 "$rpipe"

pidverif="$DIR/su_pidverif"
touch "$pidverif"
chcon u:object_r:ashmem_device:s0 "$pidverif"

echo "$PROTOCOL_VERSION" >> "$wpipe" # Version number

read -r ack < "$rpipe"
[ "$ack" = "ok" ] || { echo "protocol version mismatch!"; return 99; }

# Make sure this process is allowed su access.
# Needed because someone might be injecting logs to trick us into launching this server.

openpid=$(lsof -t "$pidverif" | cut -d , -f 1)
if [ -z "$openpid" ]; then
	echo "security check file not opened, unable to verify pid."
	exit 97
fi
echo "$openpid"
find_package_name "$openpid"
ret="$?"
echo "$ret"
[ "$ret" = "0" ] || { echo "someone is spoofing your logs. you have a malicious app. exiting. "; exit 98; }

echo "ok" >> "$wpipe"

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
echo -e '***\n***\n***'
echo "$command"
echo -e '***\n***\n***'
echo 0
# Lets start building the command we will later run.
#base and shell:
cmd="$shell"

if [ ! -z "$command" ]; then
	tmpcommand="$DIR/cmds/$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 50)"
        echo -En "$command" > "$tmpcommand" # i cba to quote everything right
	cmd="$cmd $tmpcommand"
fi
echo 1
#End the command

echo $interactive >> "$wpipe"

if [ "$interactive" = "1" ]; then
	echo 2
	cmd="$DIR/ptyproxy $cmd <> $tty >&0 2>&1" #Make $? literal, so its evaluated later, like laaaaaaaater.
else
	echo 3
	stdinpipe="$DIR/sus/$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 50)"
	stdoutpipe="$DIR/sus/$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 50)"
	stderrpipe="$DIR/sus/$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 50)"
	"$DIR/busybox" mknod "$stdinpipe" p
	"$DIR/busybox" mknod "$stdoutpipe" p
	"$DIR/busybox" mknod "$stderrpipe" p
        echo "pipes $stdinpipe $stdoutpipe $stderrpipe END"
	echo "$stdinpipe-$stdoutpipe-$stderrpipe" >> "$wpipe"
        echo pipes sent
	cmd="$cmd >$stdoutpipe <$stdinpipe 2>$stderrpipe"
fi

cmd="$cmd; echo "'$?'" >> $wpipe"

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
echo "5: $wpipe"
read -r message < "$rpipe"
echo 6
[ "$message" = "go" ] || { echo "they aborted!"; exit 20; }
"$DIR/busybox" nsenter -m$chnspath -S$chuid -- setsid /system/bin/sh -c "$cmd" &
echo 7

exit 10


