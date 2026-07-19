[CmdletBinding()]
param(
    [string]$Python = "",
    [int]$Port = 8000,
    [string]$OutputRoot = "",
    [string]$ChromeBinary = "",
    [string]$ChromeDriver = "",
    [string]$FirefoxBinary = "",
    [string]$FirefoxDriver = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $ProjectRoot ".cache\omp0-windows-campaign\$Timestamp"
} elseif (-not [System.IO.Path]::IsPathRooted($OutputRoot)) {
    $OutputRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $OutputRoot))
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath exited with code $LASTEXITCODE"
    }
}

function Find-Packet {
    param(
        [Parameter(Mandatory = $true)][string]$PacketRoot,
        [Parameter(Mandatory = $true)][string]$Browser
    )
    $Packet = Get-ChildItem -Path $PacketRoot -Directory -Filter "$Browser-*" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $Packet) {
        throw "No $Browser packet was created under $PacketRoot"
    }
    return $Packet
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$PacketRoot = Join-Path $OutputRoot "packets"
$ArchiveRoot = Join-Path $OutputRoot "archives"
$VenvRoot = Join-Path $OutputRoot ".venv"
New-Item -ItemType Directory -Force -Path $PacketRoot, $ArchiveRoot | Out-Null

if ($Python) {
    $BootstrapPython = $Python
    $BootstrapArguments = @()
} elseif (Get-Command "py.exe" -ErrorAction SilentlyContinue) {
    $BootstrapPython = "py.exe"
    $BootstrapArguments = @("-3")
} elseif (Get-Command "python.exe" -ErrorAction SilentlyContinue) {
    $BootstrapPython = "python.exe"
    $BootstrapArguments = @()
} else {
    throw "Python 3.11 or newer was not found (expected py.exe or python.exe)."
}

Push-Location $ProjectRoot
$Server = $null
$CampaignRows = @()
$CampaignExitCode = 0
try {
    & $BootstrapPython @BootstrapArguments "-c" (
        "import sys; assert sys.version_info >= (3, 11), sys.version"
    )
    if ($LASTEXITCODE -ne 0) {
        throw "Python 3.11 or newer is required."
    }
    & $BootstrapPython @BootstrapArguments "-m" "venv" $VenvRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Could not create the evidence-only Python environment."
    }

    $VenvPython = Join-Path $VenvRoot "Scripts\python.exe"
    Invoke-Checked $VenvPython @(
        "-m", "pip", "install", "--disable-pip-version-check",
        "--requirement", "scripts\browser_matrix-requirements.txt"
    )
    Invoke-Checked $VenvPython @("scripts\web_build.py", "--output", "build\web")

    $ServerStdout = Join-Path $OutputRoot "web-server.stdout.log"
    $ServerStderr = Join-Path $OutputRoot "web-server.stderr.log"
    $Server = Start-Process -FilePath $VenvPython -ArgumentList @(
        "scripts\web_serve.py", "build\web", "--host", "127.0.0.1", "--port", "$Port"
    ) -WorkingDirectory $ProjectRoot -PassThru -NoNewWindow `
        -RedirectStandardOutput $ServerStdout -RedirectStandardError $ServerStderr

    $BaseUrl = "http://127.0.0.1:$Port/"
    $Ready = $false
    for ($Attempt = 0; $Attempt -lt 60; $Attempt += 1) {
        if ($Server.HasExited) {
            throw "The artifact server exited before becoming ready; inspect $ServerStderr"
        }
        try {
            Invoke-WebRequest -UseBasicParsing -Uri "${BaseUrl}manifest.json" -TimeoutSec 2 |
                Out-Null
            $Ready = $true
            break
        } catch {
            Start-Sleep -Milliseconds 250
        }
    }
    if (-not $Ready) {
        throw "The artifact server did not become ready at $BaseUrl"
    }

    Write-Host ""
    Write-Host "ATTENDED CAMPAIGN"
    Write-Host "Keep this unlocked hardware-accelerated desktop foregrounded."
    Write-Host "For each browser, listen during the opening flow and press physical A then B."
    Write-Host "The full Chrome row runs before the full Firefox row; allow about 25-30 minutes."
    Write-Host ""

    foreach ($Browser in @("chrome", "firefox")) {
        Read-Host (
            "Ready for $Browser with speakers audible and the standard-mapped controller " +
            "connected? Press Enter"
        ) | Out-Null

        $MatrixArguments = @(
            "scripts\browser_matrix.py",
            "--browser", $Browser,
            "--url", $BaseUrl,
            "--flow-timeout", "300",
            "--stability-seconds", "600",
            "--output", $PacketRoot
        )
        if ($Browser -eq "chrome") {
            if ($ChromeBinary) {
                $MatrixArguments += @("--binary", $ChromeBinary)
            }
            if ($ChromeDriver) {
                $MatrixArguments += @("--driver", $ChromeDriver)
            }
        } else {
            if ($FirefoxBinary) {
                $MatrixArguments += @("--binary", $FirefoxBinary)
            }
            if ($FirefoxDriver) {
                $MatrixArguments += @("--driver", $FirefoxDriver)
            }
        }

        & $VenvPython @MatrixArguments
        $MatrixExitCode = $LASTEXITCODE
        if ($MatrixExitCode -ne 0) {
            $CampaignExitCode = 1
        }

        $Packet = Find-Packet $PacketRoot $Browser
        $Archive = Join-Path $ArchiveRoot "$($Packet.Name).zip"
        Compress-Archive -Path (Join-Path $Packet.FullName "*") -DestinationPath $Archive -Force
        $ArchiveHash = (Get-FileHash -Algorithm SHA256 -Path $Archive).Hash.ToLowerInvariant()
        $AudioHeard = Read-Host "Was Galactic Cup audio audible during $Browser? (yes/no/unsure)"
        $PhysicalButtons = Read-Host (
            "Did you press physical standard-mapped A then B during $Browser? (yes/no/unsure)"
        )
        $CampaignRows += [ordered]@{
            browser = $Browser
            matrix_exit_code = $MatrixExitCode
            packet = $Packet.FullName
            archive = $Archive
            archive_sha256 = $ArchiveHash
            operator_audio_audible = $AudioHeard
            operator_physical_a_then_b = $PhysicalButtons
        }
        Write-Host "Raw packet: $($Packet.FullName)"
        Write-Host "Archive: $Archive"
        Write-Host "Archive SHA-256: $ArchiveHash"
    }
} finally {
    if ($Server -and -not $Server.HasExited) {
        Stop-Process -Id $Server.Id -ErrorAction SilentlyContinue
        $Server.WaitForExit()
    }
    Pop-Location
}

$SummaryPath = Join-Path $OutputRoot "campaign-summary.json"
[ordered]@{
    captured_at = (Get-Date).ToUniversalTime().ToString("o")
    output_root = $OutputRoot
    rows = $CampaignRows
    server_stopped = ($null -eq $Server -or $Server.HasExited)
} | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 $SummaryPath

Write-Host ""
Write-Host "Campaign summary: $SummaryPath"
Write-Host "Raw packets: $PacketRoot"
Write-Host "Archives: $ArchiveRoot"
if ($CampaignExitCode -ne 0) {
    Write-Warning (
        "One or more matrix rows retained a failing or unavailable gate. " +
        "Review the packets; do not infer missing evidence as a pass."
    )
}
exit $CampaignExitCode
