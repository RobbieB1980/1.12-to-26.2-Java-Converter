<#
.SYNOPSIS
  Create/update a GitHub Release and upload portable + setup artifacts from dist/.

.EXAMPLE
  .\scripts\Publish-GitHubRelease.ps1 -Tag v0.3.0
#>
[CmdletBinding()]
param(
    [string]$Tag = 'v0.3.0',
    [string]$Repo = 'RobbieB1980/1.12-to-26.2-Java-Converter',
    [string]$Name = 'RB 1.12 to 26.2 Java Converter 0.3.0'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$Dist = Join-Path $RepoRoot 'dist'

$setup = Join-Path $Dist 'RB-112-to-262-Java-Converter-Setup.exe'
$portable = Join-Path $Dist 'RB-112-to-262-Java-Converter-Portable.zip'
if (-not (Test-Path $setup)) { throw "Missing setup EXE in dist/ - run Build-Release.ps1 first" }
if (-not (Test-Path $portable)) { throw "Missing portable ZIP in dist/ - run Build-Release.ps1 first" }

$fill = "protocol=https`nhost=github.com`n`n" | git credential fill 2>$null
$token = ($fill | Where-Object { $_ -like 'password=*' }) -replace '^password=', ''
if (-not $token) { throw 'Could not obtain GitHub credentials from git credential helper.' }

$headers = @{
    Authorization          = "Bearer $token"
    Accept                 = 'application/vnd.github+json'
    'User-Agent'           = 'RB-112-to-262-Java-Converter-Release'
    'X-GitHub-Api-Version' = '2022-11-28'
}

$api = "https://api.github.com/repos/$Repo"

$notes = @"
## RB 1.12 to 26.2 Java Converter $Tag

Experimental converter: **Forge 1.12.2** jars/projects to **NeoForge 26.2** scaffolds.

### Stage B (v0.3)

- LegacyBlock112 + Material/EnumFacing/ItemBlock/properties compile stubs
- Hospital proof: unique errors **5472 → 0**; ``compileJava`` **SUCCESS** (stub no-ops — not runtime-ready)

### Stage A (v0.2)

- Stub IProxy/ClientProxy/ServerProxy; modern ``@Mod`` + IEventBus; ServerPlayer/MobEffect fixes

### Downloads

| File | Description |
|------|-------------|
| ``RB-112-to-262-Java-Converter-Setup.exe`` | Windows installer (self-contained; embeds portable toolset; Install + Uninstall) |
| ``RB-112-to-262-Java-Converter-Portable.zip`` | No install - extract and run ``Start-Converter.bat`` |

### Install / uninstall

- Setup installs under ``%LOCALAPPDATA%\RB-112-to-262-Java-Converter`` by default (no admin)
- Uninstall via Setup button, Start Menu, ``Uninstall.cmd``, or Windows Apps and features
- App icon on Setup + main EXE

### Scope (honest)

- Decompile + mcmod.info + Stage A lifecycle stubs + 26.2 Gradle scaffold
- **Not** a full automatic port of large 1.12 MCreator mods (block APIs remain Stage B)

Separate from [LegacyJavaConverter](https://github.com/RobbieB1980/LegacyJavaConverter) (1.20.1 / 1.21.x).
"@

Write-Host "==> Checking for existing release $Tag" -ForegroundColor Cyan
$release = $null
try {
    $release = Invoke-RestMethod -Headers $headers -Uri "$api/releases/tags/$Tag" -Method Get
    Write-Host "    Release exists (id $($release.id)) - will refresh assets and notes"
    $bodyObj = @{ name = $Name; body = $notes; draft = $false; prerelease = $true } | ConvertTo-Json -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($bodyObj)
    $release = Invoke-RestMethod -Headers $headers -Uri "$api/releases/$($release.id)" -Method Patch -Body $bytes -ContentType 'application/json; charset=utf-8'
}
catch {
    Write-Host "    Creating release $Tag"
    $bodyObj = @{ tag_name = $Tag; name = $Name; body = $notes; draft = $false; prerelease = $true } | ConvertTo-Json -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($bodyObj)
    $release = Invoke-RestMethod -Headers $headers -Uri "$api/releases" -Method Post -Body $bytes -ContentType 'application/json; charset=utf-8'
}

function Upload-Asset([string]$FilePath) {
    $name = [IO.Path]::GetFileName($FilePath)
    $release = Invoke-RestMethod -Headers $headers -Uri "$api/releases/tags/$Tag" -Method Get
    if ($release.assets) {
        foreach ($a in @($release.assets | Where-Object { $_.name -eq $name })) {
            Write-Host "    Deleting existing asset $name"
            Invoke-RestMethod -Headers $headers -Uri "$api/releases/assets/$($a.id)" -Method Delete | Out-Null
        }
        $release = Invoke-RestMethod -Headers $headers -Uri "$api/releases/tags/$Tag" -Method Get
    }
    $uploadUrl = $release.upload_url -replace '\{\?name,label\}', "?name=$([uri]::EscapeDataString($name))"
    Write-Host "    Uploading $name ($([math]::Round((Get-Item $FilePath).Length/1MB,1)) MB)..."
    $fileBytes = [IO.File]::ReadAllBytes($FilePath)
    $ctype = if ($name.EndsWith('.zip')) { 'application/zip' } else { 'application/octet-stream' }
    $wc = New-Object System.Net.WebClient
    $wc.Headers['Authorization'] = "Bearer $token"
    $wc.Headers['Accept'] = 'application/vnd.github+json'
    $wc.Headers['User-Agent'] = 'RB-112-to-262-Java-Converter-Release'
    $wc.Headers['X-GitHub-Api-Version'] = '2022-11-28'
    $wc.Headers['Content-Type'] = $ctype
    try {
        [void]$wc.UploadData($uploadUrl, 'POST', $fileBytes)
    }
    finally {
        $wc.Dispose()
    }
    Write-Host "    Uploaded $name" -ForegroundColor Green
}

Upload-Asset $setup
Upload-Asset $portable

Write-Host ""
Write-Host "Release published: https://github.com/$Repo/releases/tag/$Tag" -ForegroundColor Green
