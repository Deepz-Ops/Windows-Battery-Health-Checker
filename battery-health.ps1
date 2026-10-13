
<#
.SYNOPSIS
    Windows Laptop and Battery Health Checker

.DESCRIPTION
    Collects laptop identification details and calculates battery health
    from the Windows battery report.

.PARAMETER ReportPath
    Path to generate or read the HTML battery report.

.PARAMETER UseExisting
    Reuse an existing HTML report instead of generating a new one.

.PARAMETER CsvPath
    Optional path to export the results to CSV.

.EXAMPLE
    .\battery-health.ps1

.EXAMPLE
    .\battery-health.ps1 -CsvPath "D:\battery-health.csv"

.EXAMPLE
    .\battery-health.ps1 -UseExisting

.EXAMPLE
    .\battery-health.ps1 -ReportPath "D:\Reports\battery-report.html"
#>

[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$ReportPath = (
        Join-Path $env:USERPROFILE "battery-report.html"
    ),

    [switch]$UseExisting,

    [ValidateNotNullOrEmpty()]
    [string]$CsvPath
)

$ErrorActionPreference = "Stop"

# ============================================================
# 1. GET LAPTOP INFORMATION
# ============================================================

$ComputerName = $env:COMPUTERNAME
$SerialNumber = "Unavailable"
$Manufacturer = "Unknown"
$Model = "Unknown"

try {
    $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop

    if (-not [string]::IsNullOrWhiteSpace($bios.SerialNumber)) {
        $SerialNumber = $bios.SerialNumber.Trim()
    }

    if (-not [string]::IsNullOrWhiteSpace($computer.Manufacturer)) {
        $Manufacturer = $computer.Manufacturer.Trim()
    }

    if (-not [string]::IsNullOrWhiteSpace($computer.Model)) {
        $Model = $computer.Model.Trim()
    }
}
catch {
    Write-Warning "Could not retrieve all system details: $($_.Exception.Message)"
}

# ============================================================
# 2. FUNCTION: EXTRACT BATTERY CAPACITY VALUES
# ============================================================

function Get-CapacityValues {
    param(
        [Parameter(Mandatory)]
        [string]$Html,

        [Parameter(Mandatory)]
        [string]$Label
    )

    $pattern = '(?is)<span\b[^>]*class\s*=\s*["''][^"'']*\blabel\b[^"'']*["''][^>]*>\s*' +
        [regex]::Escape($Label) +
        '\s*</span>(?:(?!</tr>).)*?<td\b[^>]*>\s*([\d,]+)\s*mWh\b'

    foreach ($match in [regex]::Matches($Html, $pattern)) {
        $number = $match.Groups[1].Value -replace ',', ''
        $capacity = [long]0

        if ([long]::TryParse($number, [ref]$capacity)) {
            $capacity
        }
    }
}

# ============================================================
# 3. FUNCTION: EXTRACT BATTERY NAMES
# ============================================================

function Get-BatteryNames {
    param(
        [Parameter(Mandatory)]
        [string]$Html
    )

    $pattern = '(?is)<span\b[^>]*class\s*=\s*["''][^"'']*\blabel\b[^"'']*["''][^>]*>\s*NAME\s*</span>(?:(?!</tr>).)*?<td\b[^>]*>\s*([^<]+)'

    foreach ($match in [regex]::Matches($Html, $pattern)) {
        $name = [System.Net.WebUtility]::HtmlDecode(
            $match.Groups[1].Value.Trim()
        )

        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $name
        }
    }
}

# ============================================================
# 4. FUNCTION: BATTERY STATUS
# ============================================================

function Get-BatteryStatus {
    param(
        [Parameter(Mandatory)]
        [double]$Health
    )

    if ($Health -ge 80) {
        "Good"
    }
    elseif ($Health -ge 60) {
        "Fair"
    }
    else {
        "Degraded"
    }
}

# ============================================================
# 5. FUNCTION: BATTERY RECOMMENDATION
# ============================================================

function Get-BatteryRecommendation {
    param(
        [Parameter(Mandatory)]
        [double]$Health
    )

    if ($Health -lt 60) {
        "Consider battery replacement"
    }
    elseif ($Health -lt 80) {
        "Monitor battery performance"
    }
    else {
        "Continue normal use"
    }
}

# ============================================================
# 6. MAIN SCRIPT
# ============================================================

try {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "       LAPTOP AND BATTERY HEALTH REPORT           " -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ""

    # Display device identification
    Write-Host "DEVICE INFORMATION" -ForegroundColor Cyan
    Write-Host "--------------------------------------------------"
    Write-Host "Computer Name : $ComputerName"
    Write-Host "Manufacturer  : $Manufacturer"
    Write-Host "Model         : $Model"
    Write-Host "Serial Number : $SerialNumber"
    Write-Host ""

    # --------------------------------------------------------
    # Generate or reuse the HTML battery report
    # --------------------------------------------------------

    if (-not $UseExisting) {
        $reportDirectory = Split-Path -Parent $ReportPath

        if (
            -not [string]::IsNullOrWhiteSpace($reportDirectory) -and
            -not (Test-Path -LiteralPath $reportDirectory -PathType Container)
        ) {
            New-Item -ItemType Directory `
                -Path $reportDirectory `
                -Force | Out-Null
        }

        Write-Host "Generating battery report..." -ForegroundColor Yellow

        $powercfgOutput = & powercfg.exe /batteryreport /output "$ReportPath" 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to generate battery report. $($powercfgOutput -join ' ')"
        }
    }
    else {
        Write-Host "Using existing battery report..." -ForegroundColor Yellow
    }

    # --------------------------------------------------------
    # Validate report
    # --------------------------------------------------------

    if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) {
        throw "Battery report not found: $ReportPath"
    }

    $reportFile = Get-Item -LiteralPath $ReportPath

    if ($reportFile.Length -eq 0) {
        throw "Battery report is empty."
    }

    $html = Get-Content -LiteralPath $ReportPath -Raw

    if ([string]::IsNullOrWhiteSpace($html)) {
        throw "Unable to read battery report."
    }

    # --------------------------------------------------------
    # Extract capacity values
    # --------------------------------------------------------

    Write-Host "Reading battery information..." -ForegroundColor Yellow

    $designValues = @(
        Get-CapacityValues -Html $html -Label "DESIGN CAPACITY"
    )

    $fullValues = @(
        Get-CapacityValues -Html $html -Label "FULL CHARGE CAPACITY"
    )

    $batteryNames = @(Get-BatteryNames -Html $html)

    if ($designValues.Count -eq 0 -or $fullValues.Count -eq 0) {
        throw "Could not find battery capacity values. Check the Windows battery report format."
    }

    if ($designValues.Count -ne $fullValues.Count) {
        throw "Design capacity and full-charge capacity counts do not match."
    }

    # --------------------------------------------------------
    # Calculate battery health
    # --------------------------------------------------------

    $results = @()

    for ($i = 0; $i -lt $designValues.Count; $i++) {
        $design = [long]$designValues[$i]
        $full = [long]$fullValues[$i]

        if ($design -le 0 -or $full -le 0) {
            Write-Warning "Skipping battery $($i + 1): invalid capacity values."
            continue
        }

        $health = [math]::Round(
            ($full / [double]$design) * 100,
            2
        )

        $capacityLost = [math]::Round(
            100 - $health,
            2
        )

        $batteryName = if (
            $i -lt $batteryNames.Count -and
            -not [string]::IsNullOrWhiteSpace($batteryNames[$i])
        ) {
            $batteryNames[$i]
        }
        else {
            "Battery $($i + 1)"
        }

        $status = Get-BatteryStatus -Health $health
        $recommendation = Get-BatteryRecommendation -Health $health

        $results += [PSCustomObject]@{
            ComputerName        = $ComputerName
            Manufacturer        = $Manufacturer
            Model               = $Model
            SerialNumber        = $SerialNumber
            Battery             = $batteryName
            DesignCapacity_mWh  = $design
            FullCharge_mWh      = $full
            HealthPercent       = $health
            CapacityLostPercent = $capacityLost
            Status              = $status
            Recommendation      = $recommendation
        }
    }

    if ($results.Count -eq 0) {
        throw "No valid battery records were found."
    }

    # --------------------------------------------------------
    # Display results
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "BATTERY HEALTH RESULTS" -ForegroundColor Cyan
    Write-Host "=================================================="

    foreach ($item in $results) {
        $color = switch ($item.Status) {
            "Good"     { "Green" }
            "Fair"     { "Yellow" }
            "Degraded" { "Red" }
            default    { "White" }
        }

        Write-Host ""
        Write-Host "Battery        : $($item.Battery)"
        Write-Host ("Design capacity: {0:N0} mWh" -f $item.DesignCapacity_mWh)
        Write-Host ("Full charge    : {0:N0} mWh" -f $item.FullCharge_mWh)

        Write-Host (
            "Battery health : {0:N2}%" -f $item.HealthPercent
        ) -ForegroundColor $color

        Write-Host (
            "Capacity lost  : {0:N2}%" -f $item.CapacityLostPercent
        )

        Write-Host "Status         : $($item.Status)" -ForegroundColor $color
        Write-Host "Recommendation : $($item.Recommendation)"
        Write-Host "--------------------------------------------------"
    }

    # --------------------------------------------------------
    # Optional CSV export
    # --------------------------------------------------------

    if ($CsvPath) {
        $csvDirectory = Split-Path -Parent $CsvPath

        if (
            -not [string]::IsNullOrWhiteSpace($csvDirectory) -and
            -not (Test-Path -LiteralPath $csvDirectory -PathType Container)
        ) {
            New-Item -ItemType Directory `
                -Path $csvDirectory `
                -Force | Out-Null
        }

        $results | Export-Csv `
            -LiteralPath $CsvPath `
            -NoTypeInformation `
            -Encoding UTF8

        Write-Host ""
        Write-Host "CSV exported successfully: $CsvPath" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "HTML Report     : $ReportPath"
    Write-Host "Serial Number   : $SerialNumber"
    Write-Host "Total Batteries : $($results.Count)"
    Write-Host ""
    Write-Host "Battery health check completed successfully." -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Battery health check failed." -ForegroundColor Red
    exit 1
}