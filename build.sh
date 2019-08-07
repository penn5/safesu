#!/bin/bash

rm -rf out
mkdir -p out/system/etc/nomagic

git submodule init
git submodule sync
git submodule update

cd busybox
make LDFLAGS=--static ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- allnoconfig
sed -i 's/^# CONFIG_NSENTER is not set$/CONFIG_NSENTER=y/' .config # Needed to mount in a specific process's domain, and for mountmode=1
sed -i 's/^# CONFIG_INOTIFYD is not set$/CONFIG_INOTIFYD=y/' .config # Needed to watch for new pipes in sureq
sed -i 's/^# CONFIG_MKNOD is not set$/CONFIG_MKNOD=y/' .config # Needed to make pipes for sureq and sus
sed -i 's/^# CONFIG_TR is not set$/CONFIG_TR=y/' .config # Needed to generate a random string
sed -i 's/^# CONFIG_HEAD is not set$/CONFIG_HEAD=y/' .config # Needed to generate a random string
sed -i 's/^# CONFIG_SETSID is not set$/CONFIG_SETSID=y/' .config # Needed to launch sh on another tty/pty
sed -i 's/^# CONFIG_REALPATH is not set$/CONFIG_REALPATH=y/' .config # Needed to sanitize untrusted input
sed -i 's/^# CONFIG_GETOPT is not set$/CONFIG_GETOPT=y/' .config # Needed to sanitize untrusted input
sed -i 's/^# CONFIG_UNSHARE is not set$/CONFIG_UNSHARE=y/' .config # Needed to make an isolated namespace
sed -i 's/^# CONFIG_LSOF is not set$/CONFIG_LSOF=y/' .config # Needed to find the pid on the other end of fifo -> cmdline -> package name
sed -i 's/^# CONFIG_FEATURE_GETOPT_LONG is not set$/CONFIG_FEATURE_GETOPT_LONG=y/' .config # Needed to have proper su compatibility.

make LDFLAGS=--static ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
cd ..
cp busybox/busybox out/system/etc/nomagic/busybox

cd ptyproxy
make LDFLAGS=--static ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
cd ..
cp ptyproxy/ptyproxy out/system/etc/nomagic/ptyproxy

cp src/*.sh out/system/etc/nomagic
