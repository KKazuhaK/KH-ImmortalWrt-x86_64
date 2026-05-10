#!/bin/bash
#
# diy-part2.sh — runs AFTER `feeds install -a`, before `make defconfig`.
# Use this to tweak default LAN IP, hostname, theme, banner, etc.
#

# Change default LAN IP (uncomment & edit)
# sed -i 's/192.168.1.1/192.168.10.1/g' package/base-files/files/bin/config_generate

# Change default hostname
# sed -i "s/hostname='.*'/hostname='ImmortalWrt'/g" package/base-files/files/bin/config_generate

# Set default theme to Argon (if argon feed is enabled)
# sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile 2>/dev/null || true
