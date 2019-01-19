VERSION=0
#. /data/adb/safesu.cfg

usage() { echo "Usage: $0 [-s <45|90>] [-p <string>]" 1>&2; exit 1; }

interactive=1
environ=0
login=0
command=""
shell="/system/bin/sh"
mountmode=$$

options=$(/system/etc/nomagic/busybox getopt -l "command:,help,login,preserve-environment,shell:,version,context:,mount-master" -o "c:hlmps:Vvz:M" -- "$@")
[ $? -eq 0 ] || {
	echo "$options"
	echo "Incorrect options provided"
	exit 1
}

eval set -- "$options"
while true; do
	echo "$1"
	case "$1" in
		-c)
			shift
			command="$1"
			interactive=0
			;;
		-l)
			interactive=1
			login=1
			;;
		-m)
			environ=1
			;;
		-p)
			environ=1
			;;
		-s)
			shift
			shell="$1"
			;;
		-v)
			echo "$VERSION"
			exit
			;;
		-V)
			echo "SafeSU $VERSION (hackintosh5)"
			exit
			;;
		-z)
			shift
			;;
		-M)
			mountmode=1
			;;
		-h)
			usage
			;;
		--)
			shift $((OPTIND - 1))
			break
	esac
done

echo "interactive=$interactive"
echo "mountmode=$mountmode"
echo "environ=$environ"
echo "login=$login"
echo "command=$command"
echo "shell=$shell"

#BEGIN MAIN CODE
rpipe=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 50)
/system/etc/nomagic/busybox mknod "/system/etc/nomagic/sus/$rpipe" p
wpipe=/system/etc/nomagic/sureq/$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 50)
/system/etc/nomagic/busybox mknod "$wpipe" p

secfile=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 50)
echo "$rpipe" > "/system/etc/nomagic/pidverif/$secfile"
touch "/system/etc/nomagic/pidverif/$secfile"
exec 3<"/system/etc/nomagic/pidverif/$secfile"
echo "$secfile" >> "$wpipe"
echo "$rpipe" >> "$wpipe"
rpipe="/system/etc/nomagic/sus/$rpipe"
read -r hello < "$rpipe"
[ "$hello" = "$VERSION" ] || (echo "incorrect hello from su_handler, got $hello!";exit 1)

exec 3<&-
rm -f "/system/etc/nomagic/pidverif/$secfile"

if [ ! -t 0 ] || [ ! -t 1 ] || [ "$interactive" = "0" ]; then
	# non-interactive
	# Send the data we want...
	echo >> "$wpipe" # tell the su_hander to make some new pipes for us.
else
	# interactive
	# Send the data we want...
	echo "$(tty | cut -d / -f 4)" >> $wpipe # tell the su_hander where to send the su process. This **could** be abused to grant root to another app but that is possible even if you use a normal kind of su, so we don't worry. If this app has root access, it probably shouldn't be abusing us anyway :/
fi
read -r message < "$rpipe"
[ "$message" = "ok" ] || { echo "didnt get okay!";exit 1; }

# Keep sending data
echo sending mntmode
echo "$mountmode" >> "$wpipe"
read -r message < "$rpipe"
[ "$message" = "ok" ] || { echo "didnt get okay!";exit 1; }
echo sent mntmode
echo sending shell
echo "$shell" >> "$wpipe"
read -r message < "$rpipe"
[ "$message" = "ok" ] || { echo "didnt get okay!";exit 1; }
echo "sent shell: $shell"

[ "$login" = "1" ] && echo "root" >> "$wpipe" || echo >> "$wpipe"
read -r message < "$rpipe"
[ "$message" = "ok" ] || { echo "didnt get okay!";exit 1; }

[ "$environ" = "1" ] && (env -0 && echo) >> "$wpipe" || echo >> "$wpipe"
read -r message < "$rpipe"
[ "$message" = "ok" ] || { echo "didnt get okay!";exit 1; }

echo "$command" >> "$wpipe"

# Check all went well, and leave stuff to happen on its own. su_handler will hijack our pty (tty unsupported rn bcos i havent implemented proper sanitization for full paths.) and launch a shell there.
read -r message < "$rpipe"
[ "$message" = "ok" ] || { echo "didnt get okay!";exit 1; }

read -r rinteractive < "$rpipe"
if [ "$interactive" = "1" ]; then
	#We don't have to do anything special, the remote will do everything for us and our tty will be taken over.
	echo "Getting a shell just for you!"
else
	#We need to read the stdin/out/err pipes from the rpipe and read them into/out of our stdio. TODO: Trap signals?
	read -r stdinpipe < "$rpipe"
	read -r stdoutpipe < "$rpipe"
	read -r stderrpipe < "$rpipe"
	dd if=/dev/stdin of=$stdinpipe &
	dd if=/dev/stdout of=$stdoutpipe &
	dd if=/dev/stderr of=$stderrpipe &
fi

echo "go" >> "$wpipe"

read -r message < "$rpipe" # and wait for completion.
[ "$message" = "done" ] || { echo "didn't get done!";exit 1; }
read -r rc < "$rpipe"
exit $rc #no need to sanitize since only root (su_handler) could have access to this pipe.
