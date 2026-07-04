#Requires -Version 7.0
<#
.SYNOPSIS
OpenChamber Windows ARM64 Builder

.DESCRIPTION
Clones a tagged release of OpenChamber, applies ARM64 build patches,
and produces a Windows ARM64 NSIS installer (.exe).

Supports both interactive local use and non-interactive CI execution.

.PARAMETER Tag
Specific git tag to build (e.g. "v1.13.9"). If omitted, the latest tag is fetched.

.PARAMETER CloneDir
Directory name for the cloned source. Defaults to "openchamber".

.PARAMETER OutputDir
Directory to copy the built installer. Defaults to "dist".

.PARAMETER NonInteractive
Skip all confirmation prompts. Implies proceeding with the latest tag
and deleting/re-cloning if the clone directory already exists.

.PARAMETER RepoUrl
Git remote URL for the OpenChamber source. Defaults to the public HTTPS URL.
#>

[CmdletBinding()]
param(
    [string]$Tag = "",
    [string]$CloneDir = "openchamber",
    [string]$OutputDir = "dist",
    [switch]$NonInteractive,
    [string]$RepoUrl = "https://github.com/openchamber/openchamber.git"
)

$ErrorActionPreference = 'Stop'
$ScriptRoot = $MyInvocation.MyCommand.Path | Split-Path -Parent
$ClonePath = Join-Path $ScriptRoot $CloneDir
$OutputPath = Join-Path $ScriptRoot $OutputDir

function Write-Info  { Write-Host '[INFO] '    -NoNewline -ForegroundColor Cyan;   Write-Host $args }
function Write-Ok    { Write-Host '[OK] '      -NoNewline -ForegroundColor Green;  Write-Host $args }
function Write-Warn2 { Write-Host '[WARN] '    -NoNewline -ForegroundColor Yellow; Write-Host $args }
function Write-Err   { Write-Host '[ERROR] '   -NoNewline -ForegroundColor Red;    Write-Host $args }
function Write-Step  { Write-Host ''; Write-Host ('==== ' + ($args -join ' ') + ' ====') -ForegroundColor White }

function Confirm-Prompt {
    param([string]$Prompt, [switch]$DefaultYes)
    if ($NonInteractive) { return $true }
    $suffix = if ($DefaultYes) { ' [Y/n] ' } else { ' [y/N] ' }
    $val = Read-Host ($Prompt + $suffix)
    if ([string]::IsNullOrWhiteSpace($val)) { return $DefaultYes.IsPresent }
    return $val.Trim().ToLower() -eq 'y'
}

# -- 1. Resolve tag --------------------------------------------------
Write-Step 'Resolving tag'
if ([string]::IsNullOrWhiteSpace($Tag)) {
    Write-Info 'Fetching latest tag from GitHub...'
    $tags = & git ls-remote --tags $RepoUrl 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Err 'Failed to fetch tags. Check network access to GitHub.'
        exit 1
    }
    $tagLines = $tags | Where-Object { $_ -match 'refs/tags/v[\d]+\.[\d]+\.[\d]+$' }
    $Tag = ($tagLines | ForEach-Object { ($_ -split '\s+')[1] -replace 'refs/tags/','' } |
        Sort-Object { [version]($_ -replace '^v','') } -Descending)[0]
    if (-not $Tag) {
        Write-Err 'No version tags found.'
        exit 1
    }
}
Write-Info "Tag: $Tag"

if (-not (Confirm-Prompt "Proceed with $Tag ?" -DefaultYes)) {
    Write-Info 'Aborted by user.'
    exit 0
}

# -- 2. Clone / re-clone ---------------------------------------------
Write-Step 'Preparing clone directory'
if (Test-Path $ClonePath) {
    Write-Warn2 "Directory already exists: $ClonePath"
    if (Confirm-Prompt 'Delete and re-clone?' -DefaultYes) {
        Remove-Item -Recurse -Force $ClonePath
        Write-Info 'Deleted.'
    } else {
        Write-Info 'Using existing directory.'
    }
}

if (-not (Test-Path $ClonePath)) {
    Write-Info "Cloning $Tag ..."
    & git clone --branch $Tag --depth 1 $RepoUrl $ClonePath
    if ($LASTEXITCODE -ne 0) {
        Write-Err 'git clone failed.'
        exit 1
    }
}

# -- 3. Install dependencies -----------------------------------------
Write-Step 'Installing dependencies (bun install)'
Push-Location $ClonePath
try {
    if (-not (Get-Command bun -ErrorAction SilentlyContinue)) {
        Write-Err 'Bun is not installed. Install via: winget install Oven-sh.Bun'
        exit 1
    }
    & bun install --frozen-lockfile
    if ($LASTEXITCODE -ne 0) {
        Write-Err 'bun install failed.'
        exit 1
    }
} finally {
    Pop-Location
}

# -- 4. Apply patches -------------------------------------------------
Write-Step 'Applying ARM64 build patches'

# 4a. prepare-opencode-cli.mjs -- force x64-baseline on win32/arm64
$prepareCliPath = Join-Path $ClonePath 'packages/electron/scripts/prepare-opencode-cli.mjs'
if (Test-Path $prepareCliPath) {
    $c = Get-Content $prepareCliPath -Raw
    $old = "if (arch === 'arm64') return { name: 'opencode-windows-arm64.zip', binary: 'opencode.exe' };"
    $new = "if (arch === 'arm64') return { name: 'opencode-windows-x64-baseline.zip', binary: 'opencode.exe' };"
    if ($c.Contains($old)) {
        $c = $c.Replace($old, $new)
        Set-Content $prepareCliPath $c -NoNewline
        Write-Ok 'Patched prepare-opencode-cli.mjs (arm64 -> x64-baseline)'
    } else {
        Write-Warn2 'prepare-opencode-cli.mjs: arm64 line not found (already patched?)'
    }
}

# 4b. node-pty binding.gyp -- disable Spectre mitigation
$nodePtyDir = Get-ChildItem -Path (Join-Path $ClonePath 'node_modules/.bun') -Directory -Filter 'node-pty@*' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($nodePtyDir) {
    $bg = Join-Path $nodePtyDir.FullName 'node_modules/node-pty/binding.gyp'
    if (Test-Path $bg) {
        $c = Get-Content $bg -Raw
        $old = "'SpectreMitigation': 'Spectre'"
        $new = "'SpectreMitigation': 'false'"
        if ($c.Contains($old)) {
            $c = $c.Replace($old, $new)
            Set-Content $bg $c -NoNewline
            Write-Ok 'Patched node-pty/binding.gyp (Spectre mitigation disabled)'
        } else {
            Write-Warn2 'node-pty/binding.gyp: Spectre line not found (already patched?)'
        }
    }
} else {
    Write-Warn2 'node-pty directory not found'
}

# -- 5. Build ---------------------------------------------------------
Write-Step 'Building OpenChamber ARM64 installer'

# Detect VS install path for vcvarsall
$vsPath = $null
$vsCandidates = @(
    'C:\Program Files\Microsoft Visual Studio\2022\Community',
    'C:\Program Files\Microsoft Visual Studio\17\Community',
    'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools',
    'C:\Program Files (x86)\Microsoft Visual Studio\2022\Community'
)
foreach ($p in $vsCandidates) {
    $vcvars = Join-Path $p 'VC\Auxiliary\Build\vcvarsall.bat'
    if (Test-Path $vcvars) { $vsPath = $p; break }
}

if (-not $vsPath) {
    Write-Err 'Visual Studio with C++ workload was not found.'
    Write-Err 'Install VS 2022 with "Desktop development with C++" workload (ARM64 toolset required).'
    exit 1
}

Write-Info "Using Visual Studio at: $vsPath"

$vcvarsBat = Join-Path $vsPath 'VC\Auxiliary\Build\vcvarsall.bat'
$buildScript = @"
@echo off
call "$vcvarsBat" arm64
cd /d "$ClonePath"
bun run electron:build
"@

$batFile = Join-Path $env:TEMP 'openchamber-arm64-build.bat'
Set-Content $batFile $buildScript -Encoding ascii

Write-Info 'Running build (this may take several minutes)...'
& cmd /c $batFile
$buildExit = $LASTEXITCODE
Remove-Item $batFile -ErrorAction SilentlyContinue

if ($buildExit -ne 0) {
    Write-Err "Build failed with exit code $buildExit"
    exit 1
}

Write-Ok 'Build completed successfully.'

# -- 6. Collect output ----------------------------------------------
Write-Step 'Collecting output'
$srcDistDir = Join-Path $ClonePath 'packages/electron/dist'
$exe = Get-ChildItem -Path $srcDistDir -Filter 'OpenChamber-*-win-arm64.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($exe) {
    Write-Ok "Installer: $($exe.FullName)"
    Write-Info "Size: $([math]::Round($exe.Length / 1MB, 1)) MB"

    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    $destExe = Join-Path $OutputPath $exe.Name
    Copy-Item $exe.FullName $destExe -Force
    Write-Ok "Copied to: $destExe"

    if (-not $NonInteractive) {
        if (Confirm-Prompt 'Open output folder?' -DefaultYes) {
            Start-Process explorer.exe $OutputPath
        }
    }
} else {
    Write-Warn2 'No .exe found in dist directory.'
    exit 1
}

Write-Host ''
Write-Ok 'Done.'