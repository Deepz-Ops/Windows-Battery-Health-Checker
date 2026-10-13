<#
  battery-health.ps1
  Generates a fresh Windows battery report and prints battery health:
      Health % = FULL CHARGE CAPACITY / DESIGN CAPACITY * 100

  Usage (PowerShell):
      .\battery-health.ps1
      .\battery-health.ps1 -ReportPath "C:\Users\deepan.sivakumar\battery-report.html"
      .\battery-health.ps1 -UseExisting     # parse the existing report, don't regenerate

  If scripts are blocked:
      powershell -ExecutionPolicy Bypass -File .\battery-health.ps1
#>

param(
    [string]$ReportPath = (Join-Path $env:USERPROFILE "battery-report.html"),
    [switch]$UseExisting
)

$ErrorActionPreference = "Stop"

# 1. Generate the report (unless told to reuse the existing one)
if (-not $UseExisting) {
    Write-Host "Generating battery report..." -ForegroundColor Cyan
    $out = powercfg /batteryreport /output "$ReportPath" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "powercfg failed: $out"
    }
}

if (-not (Test-Path $ReportPath)) {
    throw "Report not found: $ReportPath"
}

# 2. Read the HTML and pull out the capacity values (first match = 'Installed batteries' section)
$html = Get-Content -Path $ReportPath -Raw

function Get-Values([string]$label) {
    # Report layout: <span class="label">LABEL</span></td><td>64,007 mWh</td>
    # (several closing/opening tags sit between the label and the value)
    $pattern = "(?is)${label}(?:\s*<[^>]+>)+\s*([\d,]+)\s*mWh"
    [regex]::Matches($html, $pattern) | ForEach-Object { [int]($_.Groups[1].Value -replace ',', '') }
}

# Battery name(s) for display
$names = [regex]::Matches($html, '(?is)<span class="label">\s*NAME\s*</span>(?:\s*<[^>]+>)+\s*([^<]+?)\s*<') |
         ForEach-Object { $_.Groups[1].Value.Trim() }

$designAll = @(Get-Values "DESIGN CAPACITY")
$fullAll   = @(Get-Values "FULL CHARGE CAPACITY")

if ($designAll.Count -eq 0 -or $fullAll.Count -eq 0) {
    throw "Could not find DESIGN CAPACITY / FULL CHARGE CAPACITY in $ReportPath"
}

# Only the 'Installed batteries' section: one value per battery, at the start of each list
$count = [Math]::Max(1, @($names).Count)
$count = [Math]::Min($count, [Math]::Min($designAll.Count, $fullAll.Count))

Write-Host ""
for ($i = 0; $i -lt $count; $i++) {
    $design = $designAll[$i]
    $full   = $fullAll[$i]
    $pct    = [Math]::Round(($full / $design) * 100, 2)
    $wear   = [Math]::Round(100 - $pct, 2)

    $color = if ($pct -ge 80) { "Green" } elseif ($pct -ge 60) { "Yellow" } else { "Red" }
    $label = if (@($names).Count -gt $i) { $names[$i] } else { "Battery $($i + 1)" }

    Write-Host "Battery        : $label"
    Write-Host ("Design capacity: {0:N0} mWh" -f $design)
    Write-Host ("Full charge    : {0:N0} mWh" -f $full)
    Write-Host ("Battery health : {0}%" -f $pct) -ForegroundColor $color
    Write-Host ("Capacity lost  : {0}%" -f $wear)
    Write-Host ""
}