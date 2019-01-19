if [ "$(cat /sys/fs/selinux/enforce)" == "0" ]; then
	chmod 0640 $SEFOLDER/enforce
fi
chmod 0440 /sys/fs/selinux/policy

/system/bin/resetprop ro.boot.vbmeta.device_state locked
/system/bin/resetprop ro.boot.verifiedbootstate green
/system/bin/resetprop ro.boot.flash.locked 1
/system/bin/resetprop ro.boot.veritymode enforcing
/system/bin/resetprop ro.boot.warranty_bit 0
/system/bin/resetprop ro.warranty_bit 0
/system/bin/resetprop ro.debuggable 0
/system/bin/resetprop ro.secure 1
/system/bin/resetprop ro.build.type user
/system/bin/resetprop ro.build.tags release-keys
/system/bin/resetprop ro.build.selinux 0


