<#
.SYNOPSIS
  Cut an offline map region for Backtrack from the free Protomaps world map.

.DESCRIPTION
  Uses the official `pmtiles` CLI (github.com/protomaps/go-pmtiles) to copy
  only the tiles inside a bounding box from the latest Protomaps daily build
  (OpenStreetMap data, ODbL). Only the needed bytes are downloaded, not the
  ~120 GB planet.

  Output: maps\<name>.pmtiles  -> import it in the app:
  Settings -> Offline maps -> Import map file (or copy it with Android Studio
  Device Explorer to Android/data/com.erikfazlla.backtrack/files/maps/).

.EXAMPLE
  .\tools\cut_region.ps1 -Country GR -DryRun     # show size only
  .\tools\cut_region.ps1 -Country GR             # greece.pmtiles
  .\tools\cut_region.ps1 -Name attica -Bbox "23.3,37.6,24.1,38.4"
#>
param(
  [string]$Country,
  [string]$Name,
  # minLon,minLat,maxLon,maxLat
  [string]$Bbox,
  [int]$MaxZoom = 15,
  [string]$Build,          # e.g. 20261120; default = newest available
  [switch]$DryRun
)
$ErrorActionPreference = 'Stop'

# Rough country boxes (mainland + islands). Add more as needed.
$countries = @{
  'GR' = @{ name = 'greece';  bbox = '19.3,34.7,29.7,41.8' }
  'CY' = @{ name = 'cyprus';  bbox = '32.2,34.5,34.7,35.8' }
  'IT' = @{ name = 'italy';   bbox = '6.6,35.4,18.6,47.1' }
  'ES' = @{ name = 'spain';   bbox = '-9.4,35.9,4.4,43.8' }
  'FR' = @{ name = 'france';  bbox = '-5.2,41.3,9.6,51.1' }
  'AL' = @{ name = 'albania'; bbox = '19.2,39.6,21.1,42.7' }
  'BG' = @{ name = 'bulgaria';bbox = '22.3,41.2,28.7,44.3' }
}
if ($Country) {
  $c = $countries[$Country.ToUpper()]
  if (-not $c) { throw "Unknown country '$Country'. Use -Bbox minLon,minLat,maxLon,maxLat." }
  if (-not $Name) { $Name = $c.name }
  if (-not $Bbox) { $Bbox = $c.bbox }
}
if (-not $Name -or -not $Bbox) { throw 'Give -Country GR, or -Name and -Bbox.' }

$root = Split-Path -Parent $PSScriptRoot
$toolDir = Join-Path $root 'tools\bin'
$mapsDir = Join-Path $root 'maps'
New-Item -ItemType Directory -Force $toolDir, $mapsDir | Out-Null

# 1. pmtiles CLI (official release, Windows x86_64).
$exe = Join-Path $toolDir 'pmtiles.exe'
if (-not (Test-Path $exe)) {
  Write-Host 'Getting pmtiles CLI from github.com/protomaps/go-pmtiles ...'
  $rel = Invoke-RestMethod 'https://api.github.com/repos/protomaps/go-pmtiles/releases/latest'
  $asset = $rel.assets | Where-Object { $_.name -match 'Windows_x86_64\.zip$' } | Select-Object -First 1
  if (-not $asset) { throw 'No Windows build found in the latest go-pmtiles release.' }
  $zip = Join-Path $toolDir $asset.name
  Invoke-WebRequest $asset.browser_download_url -OutFile $zip
  Expand-Archive $zip -DestinationPath $toolDir -Force
  Remove-Item $zip
  Write-Host "pmtiles $($rel.tag_name) ready."
}

# 2. Newest Protomaps daily build (builds are named YYYYMMDD.pmtiles).
if (-not $Build) {
  for ($i = 0; $i -lt 10 -and -not $Build; $i++) {
    $d = (Get-Date).ToUniversalTime().AddDays(-$i).ToString('yyyyMMdd')
    try {
      Invoke-WebRequest "https://build.protomaps.com/$d.pmtiles" -Method Head -UseBasicParsing | Out-Null
      $Build = $d
    } catch { }
  }
  if (-not $Build) { throw 'No Protomaps build found in the last 10 days.' }
}
$src = "https://build.protomaps.com/$Build.pmtiles"
$out = Join-Path $mapsDir "$Name.pmtiles"

Write-Host "Region : $Name  bbox=$Bbox  maxzoom=$MaxZoom"
Write-Host "Source : $src"
$cliArgs = @('extract', $src, $out, "--bbox=$Bbox", "--maxzoom=$MaxZoom")
if ($DryRun) { $cliArgs += '--dry-run' }
& $exe @cliArgs
if ($LASTEXITCODE -ne 0) { throw "pmtiles extract failed ($LASTEXITCODE)." }

if (-not $DryRun) {
  $mb = [math]::Round((Get-Item $out).Length / 1MB)
  Write-Host "Done: $out ($mb MB)"
  Write-Host 'Next: copy it to the phone and import it in Backtrack (Settings -> Offline maps).'
}
