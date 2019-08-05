PROTOCOL_VERSION=0
#. /data/adb/safesu.cfg

usage() { echo "SafeSU v0" 1>&2
       echo "Usage: su [options] [-] [user [argument...]]" 1>&2
       echo 1>&2
       echo "Options:" 1>&2
       echo "  -c, --command COMMAND         pass COMMAND to the invoked shell" 1>&2
       echo "  -h, --help                    display this help message and exit" 1>&2
       echo "  -, -l, --login                pretend the shell to be a login shell" 1>&2
       echo "  -m, -p," 1>&2
       echo "  --preserve-environment        preserve the entire environment" 1>&2
       echo "  -s, --shell SHELL             use SHELL instead of the default $DEFAULT_SHELL" 1>&2
       echo "  -v, --version                 display version number and exit" 1>&2
       echo "  -V                            display version code and exit" 1>&2
       echo "  -mm, -M," 1>&2
       echo "  --mount-master                force run in the global mount namespace" 1>&2
       echo "  --mount-isolated              run in a new isolated mount namespace" 2>&2
       exit 1; }

interactive=1
environ=0
login=0
command=""
shell="/system/bin/sh"
mountmode=$$

options=$(/system/etc/nomagic/busybox getopt -l "command:,help,login,preserve-environment,shell:,version,context:,mount-master,mount-isolated" -o "c:hlmps:Vvz:Mi" -- "$@")
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
			echo "$PROTOCOL_VERSION"
			exit
			;;
		-V)
			echo "SafeSU $PROTOCOL_VERSION (hackintosh5)"
			exit
			;;
		-z)
			shift
			;;
		-M)
			mountmode=1
			;;
		-i)
			mountmode=0
			;;
		-h)
			usage
			;;
		--help)
			usage
			;;
		--)
			shift
			break
			;;
	esac
	shift || break
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
echo "$wpipe" > "/system/etc/nomagic/pidverif/$secfile"
touch "/system/etc/nomagic/pidverif/$secfile"
exec 3<"/system/etc/nomagic/pidverif/$secfile"
echo "$secfile-$rpipe" >> "$wpipe"
rpipe="/system/etc/nomagic/sus/$rpipe"
read -r hello < "$rpipe"

exec 3<&-

[ "$hello" = "$PROTOCOL_VERSION" ] || (echo "incorrect hello from su_handler, got $hello!";exit 1)

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
[ "$message" = "ok" ] || { echo "didnt get okay1!";exit 1; }

[ "$environ" = "1" ] && (env -0 && echo) >> "$wpipe" || echo >> "$wpipe"
read -r message < "$rpipe"
[ "$message" = "ok" ] || { echo "didnt get okay2!";exit 1; }

echo "$command" >> "$wpipe"

read -r rinteractive < "$rpipe"
echo $rinteractive

if [ "$rinteractive" = "1" ]; then
	#We don't have to do anything special, the remote will do everything for us and our tty will be taken over.
	echo "Getting a shell just for you!"
else
	#We need to read the stdin/out/err pipes from the rpipe and read them into/out of our stdio. TODO: Trap signals?
        echo "reading pipes"
	read -r stdinpipe < "$rpipe"
        echo "reading pipes $stdinpipe"
	read -r stdoutpipe < "$rpipe"
        echo "reading pipes $stdoutpipe"
	read -r stderrpipe < "$rpipe"
        echo "reading pipes $stdinpipe $stdoutpipe $stderrpipe END"
	dd if=/dev/stdin of=$stdinpipe &
	dd if=$stdoutpipe of=/dev/stdout &
	dd if=$stderrpipe of=/dev/stderr &
fi

# Check all went well, and leave stuff to happen on its own. su_handler will hijack our pty (tty unsupported rn bcos i havent implemented proper sanitization for full paths.) and launch a shell there.
read -r message < "$rpipe"
[ "$message" = "ok" ] || { echo "didnt get okay3! $message";exit 1; }

echo "go" >> "$wpipe"

# Hand over control - we have no more job here.
0<&-
1<&-
2<&-

read -r rc < "$rpipe" # and wait for completion.
echo "$rc" | grep '[^0-9]'
[ "$?" = "1" ] || { echo "didn't get retcode, got $rc!";exit 1; }
exit $rc #no need to sanitize since only root (su_handler) could have access to this pipe.
