#!/bin/bash
#
# diy-part2.sh — runs AFTER `feeds install -a`, before `make defconfig`.
# Use this to tweak default LAN IP, hostname, theme, banner, etc.
#

# Change default LAN IP (uncomment & edit)
# sed -i 's/192.168.1.1/192.168.10.1/g' package/base-files/files/bin/config_generate

# Change default hostname
# sed -i "s/hostname='.*'/hostname='ImmortalWrt'/g" package/base-files/files/bin/config_generate


# -----------------------------------------------------------------------------
# Strip clash files from small-package LuCI apps.
#
# kenzok8/small-package ships several luci-app-* packages that re-bundle a
# copy of /etc/config/<daemon> and /etc/init.d/<daemon>. ImmortalWrt's own
# native daemon package (e.g. `tailscale`, `snmpd`) also installs those exact
# paths, so opkg's check_data_file_clashes refuses the firmware assembly
# with errors like:
#
#   Package luci-app-tailscale wants to install file /etc/config/tailscale
#   But that file is already provided by package tailscale
#
# Fix: remove the daemon-owned files from the LuCI app's source before
# feeds install / package compile. Keeps the LuCI UI (htm/lua/js) but lets
# the native package own config/init.
# -----------------------------------------------------------------------------
strip_clash() {
    local daemon="$1"
    local d
    for d in \
        feeds/small8/luci-app-${daemon} \
        feeds/small8/applications/luci-app-${daemon} \
        package/feeds/small8/luci-app-${daemon}
    do
        [ -d "$d" ] || continue
        local f
        for f in \
            "$d/root/etc/init.d/${daemon}" \
            "$d/root/etc/config/${daemon}" \
            "$d/files/etc/init.d/${daemon}" \
            "$d/files/etc/config/${daemon}"
        do
            if [ -e "$f" ]; then
                echo "diy-part2: stripping clash file $f"
                rm -f -- "$f"
            fi
        done
    done
}

# Daemons whose LuCI front-end ships duplicated init/config from small-package:
for app in tailscale snmpd; do
    strip_clash "$app"
done


# -----------------------------------------------------------------------------
# Force using kenzok8/small-package's sing-box (1.13.x) instead of the
# ImmortalWrt packages feed's 1.12.25.
#
# 1.12.25 vendors github.com/sagernet/tailscale@v1.80.3-sing-box-1.12-mod.2 to
# embed Tailscale, but that fork tag is missing ~30 internal Go packages its
# own source files import (util/must, doctor/routetable, util/sysresources,
# feature/condregister, tsconst, omit, etc.). Build fails with:
#     no required module provides package github.com/sagernet/tailscale/...
# Runs 25645558352, 25651912790, 25695917689 each burned 3+ hours hitting it.
#
# small-package ships 1.13.11+ which uses a different integration path that
# isn't affected. `feeds install -a` defaults to first-wins, so the packages-
# feed copy gets installed first; we have to uninstall + force-install from
# small8 to pin to the working version.
# -----------------------------------------------------------------------------
if [ -d feeds/small8/sing-box ]; then
    echo "diy-part2: pinning sing-box to small-package feed (avoiding packages-feed 1.12.25)"
    ./scripts/feeds uninstall sing-box 2>/dev/null || true
    ./scripts/feeds install -p small8 -f sing-box
fi
