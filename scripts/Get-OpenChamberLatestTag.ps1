#Requires -Version 7.0
<#
.SYNOPSIS
Resolve the latest OpenChamber tag and decide whether a build is needed.

.DESCRIPTION
Fetches the latest tag from the upstream OpenChamber repository and compares it
against the latest GitHub release in this repository. Sets GitHub Actions outputs
for use by subsequent workflow steps.

.PARAMETER Repo
The GitHub repository in owner/repo format (e.g. "airtaxi/openchamber-windows-arm64").
Defaults to $env:GITHUB_REPOSITORY.

.PARAMETER UpstreamUrl
Git remote URL for the OpenChamber source. Defaults to the public HTTPS URL.

.PARAMETER TagOverride
Force a specific tag (e.g. "v1.13.9"). Skips upstream lookup.
#>

[CmdletBinding()]
param(
    [string]$Repo = $env:GITHUB_REPOSITORY,
    [string]$UpstreamUrl = "https://github.com/openchamber/openchamber.git",
    [string]$TagOverride = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LatestTag {
    param([string]$Remote)
    $tags = & git ls-remote --tags $Remote 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $tags) {
        throw "Failed to fetch tags from $Remote"
    }
    $tagLines = $tags | Where-Object { $_ -match 'refs/tags/v\d+\.\d+\.\d+$' }
    $validTags = $tagLines | ForEach-Object { ($_ -split '\s+')[1] -replace 'refs/tags/','' } |
        Where-Object { $_ -match '^v\d+\.\d+\.\d+$' }
    if (-not $validTags -or $validTags.Count -eq 0) { throw "No version tags found in $Remote" }
    $latest = ($validTags |
        Sort-Object { try { [version]($_ -replace '^v','') } catch { [version]'0.0.0' } } -Descending)[0]
    return $latest
}

function Get-LatestReleaseTag {
    param([string]$RepoName)
    $releases = gh release list --repo $RepoName --limit 30 --json tagName 2>$null | ConvertFrom-Json
    if (-not $releases -or $releases.Count -eq 0) { return $null }
    $validTags = $releases.tagName | Where-Object { $_ -match '^v\d+\.\d+\.\d+$' }
    if (-not $validTags -or $validTags.Count -eq 0) { return $null }
    $latest = ($validTags |
        Sort-Object { try { [version]($_ -replace '^v','') } catch { [version]'0.0.0' } } -Descending)[0]
    if ($latest -notmatch '^v\d+\.\d+\.\d+$') { return $null }
    return $latest
}

# -- Resolve upstream tag ----------------------------------------------
if ([string]::IsNullOrWhiteSpace($TagOverride)) {
    Write-Host "Fetching latest tag from upstream: $UpstreamUrl"
    $upstreamTag = Get-LatestTag -Remote $UpstreamUrl
} else {
    Write-Host "Using tag override: $TagOverride"
    $upstreamTag = $TagOverride.Trim()
}

Write-Host "Upstream tag:      $upstreamTag"

# -- Resolve latest release in this repo -------------------------------
$latestReleaseTag = Get-LatestReleaseTag -RepoName $Repo
Write-Host "Latest release:    $(if ($latestReleaseTag) { $latestReleaseTag } else { '(none)' })"

# -- Decide whether to build ------------------------------------------
$shouldBuild = $false
if ([string]::IsNullOrWhiteSpace($latestReleaseTag)) {
    $shouldBuild = $true
    Write-Host "No existing release found. Build needed."
} elseif (([version]($upstreamTag -replace '^v','')) -gt ([version]($latestReleaseTag -replace '^v',''))) {
    $shouldBuild = $true
    Write-Host "Upstream tag is newer than latest release. Build needed."
} else {
    Write-Host "Latest release is up to date. No build needed."
}

# -- Emit outputs ------------------------------------------------------
$version = $upstreamTag -replace '^v',''

Write-Host ""
Write-Host "Summary:"
Write-Host "  upstream_tag:      $upstreamTag"
Write-Host "  version:           $version"
Write-Host "  latest_release:    $latestReleaseTag"
Write-Host "  should_build:      $shouldBuild"

if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_OUTPUT)) {
    "upstream_tag=$upstreamTag"       >> $env:GITHUB_OUTPUT
    "version=$version"                >> $env:GITHUB_OUTPUT
    "latest_release=$latestReleaseTag" >> $env:GITHUB_OUTPUT
    "should_build=$shouldBuild".ToLower() >> $env:GITHUB_OUTPUT
}

exit 0