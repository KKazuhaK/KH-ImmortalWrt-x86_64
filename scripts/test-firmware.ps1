#Requires -Version 5.1

<#
.SYNOPSIS
    Download the latest ImmortalWrt x86 firmware Release and boot it in QEMU
    with port forwarding, so LuCI is reachable at http://localhost:<HttpPort>.

.PARAMETER Target
    Which target image to test: 'x86_64' (default) or 'x86_generic'.

.PARAMETER Variant
    Image variant. 'squashfs-combined' (BIOS, default) — just works without
    extra firmware files. 'ext4-combined' is also valid. Avoid '*-efi' here
    unless you also supply -bios <path to OVMF.fd>.

.PARAMETER HttpPort
    Host port forwarded to guest's port 80 (LuCI HTTP). Default: 8080.

.PARAMETER SshPort
    Host port forwarded to guest's port 22 (Dropbear). Default: 2222.

.PARAMETER Memory
    VM memory in MB. Default: 512 (OpenWrt is happy with this).

.PARAMETER Cpus
    Number of vCPUs. Default: 2.

.PARAMETER Force
    Re-download even if a cached .img already exists.

.PARAMETER NoBrowser
    Don't auto-open the browser to LuCI after ~30 seconds.

.EXAMPLE
    .\scripts\test-firmware.ps1
    Boot the latest x86_64 BIOS image, open browser to LuCI automatically.

.EXAMPLE
    .\scripts\test-firmware.ps1 -Target x86_generic -HttpPort 9000
    Test the 32-bit image with LuCI on http://localhost:9000.

.EXAMPLE
    .\scripts\test-firmware.ps1 -Force
    Re-download and test (use after a new release has been published).
#>
[CmdletBinding()]
param(
    [ValidateSet('x86_64', 'x86_generic')]
    [string]$Target = 'x86_64',

    [string]$Variant = 'squashfs-combined',

    [int]$HttpPort = 8080,
    [int]$SshPort  = 2222,
    [int]$Memory   = 512,
    [int]$Cpus     = 2,
    [switch]$Force,
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- locate qemu-system-x86_64 ---
$qemuCmd = Get-Command qemu-system-x86_64.exe -ErrorAction SilentlyContinue
if ($qemuCmd) {
    $qemuExe = $qemuCmd.Source
} elseif (Test-Path 'C:\Program Files\qemu\qemu-system-x86_64.exe') {
    $qemuExe = 'C:\Program Files\qemu\qemu-system-x86_64.exe'
} else {
    Write-Error "qemu-system-x86_64 not found. Install with: winget install QEMU.QEMU"
    exit 1
}

# --- locate gh CLI ---
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "GitHub CLI (gh) not found. Install with: winget install GitHub.cli"
    exit 1
}

# --- compute filename for the requested target ---
$prefix = switch ($Target) {
    'x86_64'      { 'immortalwrt-x86-64-generic' }
    'x86_generic' { 'immortalwrt-x86-generic-generic' }
}
$gzPattern = "$prefix-$Variant.img.gz"
$imgFile   = "$prefix-$Variant.img"

# --- prepare cache dir ---
$cacheDir = Join-Path $PSScriptRoot '..\.test-cache'
if (-not (Test-Path $cacheDir)) {
    New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
}
$cacheDir = (Resolve-Path -LiteralPath $cacheDir).Path

Push-Location $cacheDir
try {
    if ($Force -or -not (Test-Path $imgFile)) {
        if (Test-Path $imgFile)   { Remove-Item $imgFile }
        if (Test-Path $gzPattern) { Remove-Item $gzPattern }

        Write-Host "Fetching latest release asset matching $gzPattern ..." -ForegroundColor Cyan
        & gh release download --pattern $gzPattern --clobber
        if ($LASTEXITCODE -ne 0) {
            throw "gh release download failed — has a Release been published yet?"
        }
        if (-not (Test-Path $gzPattern)) {
            throw "gh succeeded but $gzPattern is missing — Release may not contain this target/variant."
        }

        Write-Host "Decompressing $gzPattern -> $imgFile ..." -ForegroundColor Cyan
        $inFs = [System.IO.File]::OpenRead($gzPattern)
        try {
            $outFs = [System.IO.File]::Create($imgFile)
            try {
                $gz = New-Object System.IO.Compression.GZipStream(
                    $inFs, [System.IO.Compression.CompressionMode]::Decompress)
                try { $gz.CopyTo($outFs) }
                finally { $gz.Dispose() }
            } finally { $outFs.Dispose() }
        } finally { $inFs.Dispose() }
        Remove-Item $gzPattern
    } else {
        Write-Host "Reusing cached $imgFile (pass -Force to re-download)" -ForegroundColor DarkGray
    }

    # --- schedule browser open in 30s (best-effort, runs in detached PowerShell) ---
    if (-not $NoBrowser) {
        $url = "http://localhost:$HttpPort"
        Start-Process powershell -WindowStyle Hidden -ArgumentList @(
            '-NoProfile', '-Command',
            "Start-Sleep -Seconds 30; Start-Process '$url'"
        ) | Out-Null
    }

    # --- launch QEMU foreground; user sees boot log via -serial mon:stdio ---
    Write-Host ""
    Write-Host "Booting ImmortalWrt ($Target / $Variant) in QEMU..." -ForegroundColor Green
    Write-Host ("  LuCI  : http://localhost:{0}  (auto-open in ~30s)" -f $HttpPort)
    Write-Host ("  SSH   : ssh root@localhost -p {0}" -f $SshPort)
    Write-Host  "  Quit  : Ctrl-A, then X"
    Write-Host  "  Image : $cacheDir\$imgFile"
    Write-Host ""

    $netdev = "user,id=net0,hostfwd=tcp::$HttpPort-:80,hostfwd=tcp::$SshPort-:22"

    & $qemuExe `
        -m $Memory `
        -smp $Cpus `
        -drive "file=$imgFile,format=raw" `
        -netdev $netdev `
        -device virtio-net,netdev=net0 `
        -display none `
        -serial mon:stdio
} finally {
    Pop-Location
}
