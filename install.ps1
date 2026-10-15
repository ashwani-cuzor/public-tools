<#
.SYNOPSIS
  Install the pinned PCB-layout toolchain (Java 17 + Freerouting 1.9.0, optionally KiCad 10)
  from official upstream releases, verified against toolchain.lock.

.DESCRIPTION
  Downloads only from the URLs in toolchain.lock and refuses any file whose SHA-256 does not
  match. Nothing is installed system-wide unless -InstallKiCad is given (KiCad's own installer,
  which asks for admin rights). Java and Freerouting go into -Dest, and tools.json is written
  there for the layout kit to find.

.PARAMETER Dest
  Install folder. Default: $env:CZL_TOOLS, else %LOCALAPPDATA%\cuzor-tools.

.PARAMETER InstallKiCad
  Also download the pinned KiCad installer, verify it and run it (interactive, needs admin).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File install.ps1
#>
param(
    [string]$Dest = $(if ($env:CZL_TOOLS) { $env:CZL_TOOLS } else { Join-Path $env:LOCALAPPDATA 'cuzor-tools' }),
    [switch]$InstallKiCad
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'      # Invoke-WebRequest is very slow with the progress bar

$lockPath = Join-Path $PSScriptRoot 'toolchain.lock'
$lock = Get-Content -Raw -Path $lockPath | ConvertFrom-Json
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
New-Item -ItemType Directory -Force -Path $Dest | Out-Null
$cache = Join-Path $Dest 'downloads'
New-Item -ItemType Directory -Force -Path $cache | Out-Null

function Get-Verified($item) {
    $file = Join-Path $cache $item.file
    if (Test-Path $file) {
        if ((Get-FileHash -Algorithm SHA256 $file).Hash.ToLower() -eq $item.sha256) { return $file }
        Remove-Item $file -Force
    }
    Write-Host "download $($item.url)"
    Invoke-WebRequest -UseBasicParsing -Uri $item.url -OutFile $file
    $got = (Get-FileHash -Algorithm SHA256 $file).Hash.ToLower()
    if ($got -ne $item.sha256) {
        Remove-Item $file -Force
        throw "SHA-256 mismatch for $($item.file): got $got, want $($item.sha256). Aborting."
    }
    Write-Host "  sha256 ok"
    return $file
}

# Java 17 (portable JRE)
$jkey = "windows-$arch"
if (-not $lock.java.$jkey) { $jkey = 'windows-x64' }
$jre = Get-Verified $lock.java.$jkey
$jreDir = Join-Path $Dest 'jre17'
if (-not (Test-Path (Join-Path $jreDir 'bin\java.exe'))) {
    $tmp = Join-Path $Dest 'jre_extract'
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    Expand-Archive -Path $jre -DestinationPath $tmp
    $inner = Get-ChildItem $tmp | Select-Object -First 1
    if (Test-Path $jreDir) { Remove-Item -Recurse -Force $jreDir }
    Move-Item $inner.FullName $jreDir
    Remove-Item -Recurse -Force $tmp
}
$java = Join-Path $jreDir 'bin\java.exe'

# Freerouting
$fr = Get-Verified $lock.freerouting
$jar = Join-Path $Dest $lock.freerouting.file
Copy-Item $fr $jar -Force

# KiCad
function Find-KiCadCli {
    $c = Get-Command kicad-cli -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $dirs = Get-ChildItem 'C:\Program Files\KiCad' -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending
    foreach ($d in $dirs) {
        $p = Join-Path $d.FullName 'bin\kicad-cli.exe'
        if (Test-Path $p) { return $p }
    }
    return $null
}
$cli = Find-KiCadCli
if (-not $cli -and $InstallKiCad) {
    $kkey = "windows-$arch"
    $setup = Get-Verified $lock.kicad.$kkey
    Write-Host "running the KiCad $($lock.kicad.version) installer (it asks for admin rights)"
    Start-Process -FilePath $setup -Wait
    $cli = Find-KiCadCli
}
$kver = $null
if ($cli) { $kver = (& $cli version).Trim() }

$manifest = [ordered]@{
    toolchain       = $lock.id
    java            = $java
    freerouting_jar = $jar
    kicad_cli       = $cli
    kicad_version   = $kver
}
$manifest | ConvertTo-Json | Set-Content -Encoding utf8 -Path (Join-Path $Dest 'tools.json')

Write-Host ""
Write-Host "toolchain $($lock.id) -> $Dest"
Write-Host "  java        $java"
Write-Host "  freerouting $jar"
if (-not $cli) {
    Write-Host "  kicad       NOT FOUND - install KiCad $($lock.kicad.version) (rerun with -InstallKiCad)"
    exit 2
}
elseif (-not $kver.StartsWith($lock.kicad.accept_prefix)) {
    Write-Host "  kicad       $kver at $cli - need $($lock.kicad.accept_prefix).x (rerun with -InstallKiCad)"
    exit 2
}
Write-Host "  kicad       $kver ($cli)"
Write-Host "OK"
