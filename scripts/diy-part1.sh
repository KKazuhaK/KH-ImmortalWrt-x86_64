#!/bin/bash
#
# diy-part1.sh — runs after feeds.conf is copied, BEFORE `feeds update -a`.
# Use this to add or override third-party feeds.
#
# Examples:
#   echo 'src-git small8 https://github.com/kenzok8/small-package' >> feeds.conf.default
#   echo 'src-git kenzo https://github.com/kenzok8/openwrt-packages' >> feeds.conf.default
#

# (uncomment to add the small-package feed — popular for x86_64 home routers)
# echo 'src-git small8 https://github.com/kenzok8/small-package' >> feeds.conf.default
