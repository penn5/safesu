PROTOCOL_VERSION=1
#. /data/adb/safesu.cfg

DIR="$(realpath "$(dirname "$(readlink -f "$0")")")"

origargs="$@"

dbg() { return $((1-$debug)); }

usage() { echo "SafeSU v0" 1>&2
	echo "Usage: su [options] [-] [user [argument...]]" 1>&2
	echo 1>&2
	echo "Options:" 1>&2
	echo "  -c, --command COMMAND         pass COMMAND to the invoked shell" 1>&2
	echo "  -h, --help                    display this help message and exit" 1>&2
	echo "  -, -l, --login                make the shell pretend to be a login shell" 1>&2
	echo "  -m, -p," 1>&2
	echo "  --preserve-environment        preserve the entire environment" 1>&2
	echo "  -s, --shell SHELL             use SHELL instead of the default $DEFAULT_SHELL" 1>&2
	echo "  -v, --version                 display version number and exit" 1>&2
	echo "  -V                            display version code and exit" 1>&2
	echo "  -mm, -M," 1>&2
	echo "  --mount-master                force run in the global mount namespace" 1>&2
	echo "  --mount-isolated              run in a new isolated mount namespace" 1>&2
	echo "  -d --debug                    print all debug output" 1>&2
	exit 1
}

interactive=1
environ=0
login=0
command=""
shell="/system/bin/sh"
mountmode=$$
debug=0

options=$("$DIR/busybox" getopt -l "command:,help,login,preserve-environment,shell:,version,context:,mount-master,mount-isolated,debug" -o "c:hlmps:Vvz:Mid" -- "$@")
[ $? -eq 0 ] || {
	echo "$options"
	echo "Incorrect options provided"
	exit 1
}
eval set -- "$options"
while true; do
	case "$1" in
		-c|--command)
			shift
			command="$1"
			interactive=0
			;;
		-l|--login|-)
			interactive=1
			login=1
			;;
		-m|-p|--preserve-environment)
			environ=1
			;;
		-s|--shell)
			shift
			shell="$1"
			;;
		-v)
			echo "$PROTOCOL_VERSION"
			exit
			;;
		-V|--version)
			echo "SafeSU $PROTOCOL_VERSION (hackintosh5)"
			exit
			;;
		-z)
			shift
			;;
		-M|-mm|--mount-master)
			mountmode=1
			;;
		-i|--mount-isolated)
			mountmode=0
			;;
		-d|--debug)
			debug=1
			;;
		-h|--help)
			usage
			;;
		--)
			shift
			break
			;;
	esac
	shift || break
done

dbg && {
	echo "interactive=$interactive"
	echo "mountmode=$mountmode"
	echo "environ=$environ"
	echo "login=$login"
	echo "command=$command"
	echo "shell=$shell"
}

#BEGIN MAIN CODE
rpipe="$DIR/su_read.pipe"
wpipe="$DIR/su_read.pipe"

secfile="$DIR/su_pidverif"



read -r hello < "$rpipe"

[ "$hello" = "$PROTOCOL_VERSION" ] || { echo "incorrect hello from su_handler, got $hello!"; echo "no" >> "$wpipe"; exit 1; }

# Open the security verification file to make prove who we are
exec 3<"$secfile"

echo "ok" >> "$wpipe"
read -r ack < "$rpipe"
[ "$ack" = "ok" ] || { echo "pid verification failed"; exit 99; }

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
dbg && echo sending mntmode
echo "$mountmode" >> "$wpipe"
read -r message < "$rpipe"
[ "$message" = "ok" ] || { echo "didnt get okay!";exit 1; }
dbg && echo sent mntmode
dbg && echo sending shell
echo "$shell" >> "$wpipe"
read -r message < "$rpipe"
[ "$message" = "ok" ] || { echo "didnt get okay!";exit 1; }
dbg && echo "sent shell: $shell"

[ "$login" = "1" ] && echo "root" >> "$wpipe" || echo >> "$wpipe"
read -r message < "$rpipe"
[ "$message" = "ok" ] || { echo "didnt get okay1!";exit 1; }

[ "$environ" = "1" ] && (env -0 && echo) >> "$wpipe" || echo >> "$wpipe"
read -r message < "$rpipe"
[ "$message" = "ok" ] || { echo "didnt get okay2!";exit 1; }

echo "$command" >> "$wpipe"

read -r rinteractive < "$rpipe"
dbg && echo rinteractive $rinteractive

if [ "$rinteractive" = "1" ]; then
	#We don't have to do anything special, the remote will do everything for us and our tty will be taken over.
	dbg && echo "Getting a shell just for you!"

	# Hand over control - we have no more work here.
	0<&-
	1<&-
	2<&-
else
	#We need to read the stdin/out/err pipes from the rpipe and read them into/out of our stdio. TODO: Trap signals?
	dbg && echo "reading pipes"
	read -r pipes < "$rpipe"
	stdinpipe=$(echo "$pipes" | cut -d - -f 1)
	stdoutpipe=$(echo "$pipes" | cut -d - -f 2)
	stderrpipe=$(echo "$pipes" | cut -d - -f 3)
	dbg && echo "read pipes $stdinpipe $stdoutpipe $stderrpipe END"
	cat >$stdinpipe 2>/dev/null &
	cat $stdoutpipe &
	cat $stderrpipe >&2 &
fi

# Check all went well, and leave stuff to happen on its own. su_handler will hijack our pty (tty unsupported rn bcos i havent implemented proper sanitization for full paths.) and launch a shell there if we are interactive, otherwise we already spawned cat.
read -r message < "$rpipe"
[ "$message" = "ok" ] || { echo "didnt get okay3! $message";exit 1; }

echo "go" >> "$wpipe"
read -r rc < "$rpipe" || read -r rc < "$rpipe"
echo "$rc" | grep '[^0-9]'
[ "$?" = "1" ] || { echo "didn't get retcode, got $rc!";exit 1; }
exit $rc
