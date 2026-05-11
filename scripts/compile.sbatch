#!/bin/bash
#SBATCH --job-name=immortalwrt-x86_64
#SBATCH --cpus-per-task=16
#SBATCH --mem=24G
#SBATCH --time=08:00:00
#SBATCH --output=%x-%j.log
#
# Resource sizing notes:
#   --cpus-per-task : OpenWrt build is heavily parallel — adding cores is
#                     near-linear. 16 cores is a good balance: most SLURM
#                     partitions allow it, and cold-build time drops to
#                     roughly 45min (vs ~90min at 8c). If your partition
#                     rejects 16, fall back to 12 or 8.
#   --mem           : 24G covers parallel link stages without OOM. Each
#                     link can use 4-8 GB; multiple in flight at 16-way
#                     parallel need headroom.
#   --time          : 8h is generous — actual builds are 1-2h. Leaving
#                     buffer for upstream mirror slowdowns or a first
#                     cold build with no cache.
#
# Inspect your cluster's limits first if a request gets rejected:
#   sinfo                            # see partitions and node specs
#   scontrol show partition <name>   # max CPUs/mem/time per job
#   sacctmgr show user $USER -s      # any per-user quotas

# Build ImmortalWrt x86_64 firmware on a SLURM cluster (or any Linux host)
# applying the same configs/x86_64.config + diy-part2.sh + feeds.conf.default
# this repo's GitHub Actions workflow uses.
#
# Usage on a SLURM head node (e.g. openlab.ics.uci.edu):
#     git clone https://github.com/KKazuhaK/KH-ImmortalWrt-x86_64.git ~/kh
#     cd ~/kh
#     sbatch scripts/compile.sbatch
#     squeue -u $USER                   # check status
#     tail -f immortalwrt-x86_64-*.log  # follow build
#
# Or run directly without SLURM (the #SBATCH lines are just comments to bash):
#     bash scripts/compile.sbatch
#
# Tunables (override via env before sbatch):
#     REPO_BRANCH    upstream ImmortalWrt branch (default: openwrt-24.10)
#     WORK_DIR       where build_dir + ccache + dl live (default: $HOME/immortalwrt-build)
#                    keep this persistent across runs for cache reuse
#     OUTPUT_DIR     where final firmware images are copied (default: $PWD/firmware-output)
#
# Output:
#     OUTPUT_DIR/immortalwrt-x86-64-generic-*-combined*.img.gz
#     OUTPUT_DIR/immortalwrt-x86-64-generic-rootfs.tar.gz
#     OUTPUT_DIR/sha256sums, *.manifest, *.buildinfo

set -euo pipefail

# -- config ---------------------------------------------------------------
REPO_URL=${REPO_URL:-https://github.com/immortalwrt/immortalwrt}
REPO_BRANCH=${REPO_BRANCH:-openwrt-24.10}
# When submitted via sbatch, SLURM copies this script to /var/spool/slurmd.spool
# and runs it from there — $(dirname "$0") then resolves to the spool dir, not
# the repo. SLURM also exports SLURM_SUBMIT_DIR pointing at the user's PWD at
# submit time (which is ~/kh/), so prefer that when running under SLURM.
KH_CONF_DIR=${KH_CONF_DIR:-${SLURM_SUBMIT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}}
WORK_DIR=${WORK_DIR:-$HOME/immortalwrt-build}
# Output goes into the repo's firmware-output/ subdir regardless of how the
# script was launched, so users always know where to find the binaries.
OUTPUT_DIR=${OUTPUT_DIR:-$KH_CONF_DIR/firmware-output}

echo "============ ImmortalWrt SLURM Build ============"
echo " Source         : $REPO_URL ($REPO_BRANCH)"
echo " Config root    : $KH_CONF_DIR"
echo " Build dir      : $WORK_DIR  (persistent for cache reuse)"
echo " Output dir     : $OUTPUT_DIR"
echo " CPUs available : $(nproc)"
echo " Hostname       : $(hostname)"
echo "================================================="

# -- dependency sanity check ----------------------------------------------
missing=()
for cmd in git make gcc g++ python3 unzip wget tar gzip rsync; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if [ ${#missing[@]} -gt 0 ]; then
    echo "ERROR: missing required commands: ${missing[*]}" >&2
    echo "       OpenWrt's build deps are listed at:" >&2
    echo "       https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem" >&2
    echo "       On openlab these should already be installed; if not, try:" >&2
    echo "         module load gcc python3 git" >&2
    exit 1
fi

mkdir -p "$WORK_DIR" "$OUTPUT_DIR"
cd "$WORK_DIR"

# -- clone or update immortalwrt source -----------------------------------
if [ ! -d openwrt/.git ]; then
    echo "Cloning fresh: $REPO_URL ($REPO_BRANCH)..."
    git clone --depth=1 --branch "$REPO_BRANCH" "$REPO_URL" openwrt
else
    echo "Updating existing openwrt checkout..."
    cd openwrt
    # Preserve dl/, build_dir/, staging_dir/, .ccache/ across runs
    git fetch --depth=1 origin "$REPO_BRANCH"
    git reset --hard FETCH_HEAD
    cd ..
fi

cd openwrt

# -- append custom feeds (same logic as the workflow) ---------------------
if [ -f "$KH_CONF_DIR/feeds.conf.default" ]; then
    extra=$(grep -E '^[[:space:]]*src-(git|link|cpy|bzr|svn|hg)\b' "$KH_CONF_DIR/feeds.conf.default" || true)
    if [ -n "$extra" ]; then
        echo "Appending custom feeds:"
        printf '  %s\n' "$extra"
        [ -n "$(tail -c1 feeds.conf.default)" ] && echo >> feeds.conf.default
        printf '%s\n' "$extra" >> feeds.conf.default
    fi
fi

# -- diy-part1 (pre-feeds-update tweaks) ----------------------------------
if [ -f "$KH_CONF_DIR/scripts/diy-part1.sh" ]; then
    echo "Running diy-part1.sh..."
    bash "$KH_CONF_DIR/scripts/diy-part1.sh"
fi

# -- update + install feeds ----------------------------------------------
echo "Updating feeds..."
./scripts/feeds update -a
echo "Installing feeds..."
./scripts/feeds install -a

# -- diy-part2 (post-feeds-install patches, e.g. clash-stripping) --------
if [ -f "$KH_CONF_DIR/scripts/diy-part2.sh" ]; then
    echo "Running diy-part2.sh..."
    bash "$KH_CONF_DIR/scripts/diy-part2.sh"
fi

# -- apply seed config ----------------------------------------------------
cp "$KH_CONF_DIR/configs/x86_64.config" .config
make defconfig

# -- download package sources --------------------------------------------
echo "Downloading package sources..."
make download -j8 || make download -j1 V=s
find dl -size -1024c -exec rm -f {} \; 2>/dev/null || true

# -- compile --------------------------------------------------------------
echo "Starting compile with $(nproc) threads..."
date
time (make -j"$(nproc)" || make -j1 V=s)
date

# -- copy outputs ---------------------------------------------------------
cd bin/targets/x86/64
rm -rf packages

# Same trim as the workflow's Organize files step
shopt -s nullglob
trim=(*-kernel.bin *-rootfs.img.gz *-rootfs-squashfs.img *-initramfs* *-recovery.*
      *-bl2.img *-bl31.bin *-fip.bin *-bl2-bl31.bin *-bl2-bl31-fip.bin
      *-preloader.bin *-tee.bin *-u-boot.bin *-u-boot*.fip
      *.dtb *.elf *.fit *.uImage)
for pat in "${trim[@]}"; do rm -f -- $pat; done

echo "Copying firmware to $OUTPUT_DIR ..."
rm -rf "$OUTPUT_DIR"/*
cp -v ./* "$OUTPUT_DIR/" 2>/dev/null || true

echo ""
echo "============ Build complete ============"
ls -lh "$OUTPUT_DIR"
echo "========================================"
echo ""
echo "Pull firmware to your local machine with:"
echo "  scp openlab:$OUTPUT_DIR/immortalwrt-x86-64-generic-squashfs-combined-efi.img.gz ."
