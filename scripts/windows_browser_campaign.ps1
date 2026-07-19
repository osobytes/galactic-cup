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
} else {
    $OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
}

$ProjectPrefix = $ProjectRoot.TrimEnd("\") + "\"
$CachePrefix = (Join-Path $ProjectRoot ".cache").TrimEnd("\") + "\"
if (
    $OutputRoot.StartsWith($ProjectPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and
    -not $OutputRoot.StartsWith($CachePrefix, [System.StringComparison]::OrdinalIgnoreCase)
) {
    throw "OutputRoot inside the repository must be under the ignored .cache directory."
}
if (Test-Path -LiteralPath $OutputRoot) {
    throw "OutputRoot already exists; choose a new empty path to prevent stale evidence: $OutputRoot"
}

New-Item -ItemType Directory -Path $OutputRoot | Out-Null
$PacketRoot = Join-Path $OutputRoot "packets"
$ArchiveRoot = Join-Path $OutputRoot "archives"
$VenvRoot = Join-Path $OutputRoot ".venv"
$SeleniumCache = Join-Path $OutputRoot "selenium-cache"
$SummaryPath = Join-Path $OutputRoot "campaign-summary.json"
New-Item -ItemType Directory -Path $PacketRoot, $ArchiveRoot, $SeleniumCache | Out-Null

$env:SE_CACHE_PATH = $SeleniumCache
$env:SE_AVOID_STATS = "true"
$env:SE_SKIP_DRIVER_IN_PATH = "true"

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

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )
    $Value | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 $Path
}

function Read-Decision {
    param([Parameter(Mandatory = $true)][string]$Prompt)
    while ($true) {
        $Decision = (Read-Host "$Prompt (yes/no/unsure)").Trim().ToLowerInvariant()
        if ($Decision -in @("yes", "no", "unsure")) {
            return $Decision
        }
        Write-Warning "Enter exactly yes, no, or unsure."
    }
}

function Read-PositiveInteger {
    param([Parameter(Mandatory = $true)][string]$Prompt)
    while ($true) {
        $RawValue = (Read-Host $Prompt).Trim()
        $ParsedValue = [long]0
        if ([long]::TryParse($RawValue, [ref]$ParsedValue) -and $ParsedValue -gt 0) {
            return $ParsedValue
        }
        Write-Warning "Enter a positive integer number of bytes."
    }
}

function Get-OnlyPacket {
    param([Parameter(Mandatory = $true)][string]$RowRoot)
    $Packets = @(Get-ChildItem -LiteralPath $RowRoot -Directory)
    if ($Packets.Count -ne 1) {
        throw "Expected exactly one new packet under $RowRoot; found $($Packets.Count)."
    }
    return $Packets[0]
}

function Get-FileEvidence {
    param([Parameter(Mandatory = $true)][string]$Path)
    $Item = Get-Item -LiteralPath $Path
    if ($Item.Length -le 0) {
        throw "Evidence file is empty: $Path"
    }
    return [ordered]@{
        name = $Item.Name
        path = $Item.FullName
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
        size_bytes = $Item.Length
    }
}

function Wait-ForCheckpoint {
    param(
        [Parameter(Mandatory = $true)][datetime]$Deadline,
        [Parameter(Mandatory = $true)][string]$Label
    )
    while ((Get-Date) -lt $Deadline) {
        $Remaining = [math]::Ceiling(($Deadline - (Get-Date)).TotalSeconds)
        Write-Host "$Label checkpoint in $Remaining seconds..." -NoNewline
        Start-Sleep -Seconds ([math]::Min(30, [math]::Max(1, $Remaining)))
        Write-Host "`r" -NoNewline
    }
    Write-Host ""
}

function Capture-FirefoxHeapCheckpoint {
    param(
        [Parameter(Mandatory = $true)][string]$HeapRoot,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][datetime]$BaselineAt
    )
    $AboutMemoryName = "about-memory-$Label.json.gz"
    $SnapshotName = "heap-$Label.fxsnapshot"
    Write-Host ""
    Write-Host "CHECKPOINT $Label"
    Write-Host "1. In about:memory, click Minimize memory usage, then Measure and save as:"
    Write-Host "   $(Join-Path $HeapRoot $AboutMemoryName)"
    Write-Host "2. Immediately return to the game tab's Memory panel, take a tab snapshot,"
    Write-Host "   switch to Aggregate view, and save it as:"
    Write-Host "   $(Join-Path $HeapRoot $SnapshotName)"
    Write-Host "3. Record the tab snapshot's whole-heap Total Bytes value (not file size or RSS)."
    $TotalBytes = Read-PositiveInteger "Whole-tab heap Total Bytes at $Label"
    Read-Host "Press Enter after both files are fully saved" | Out-Null
    $AboutMemory = Get-FileEvidence (Join-Path $HeapRoot $AboutMemoryName)
    $Snapshot = Get-FileEvidence (Join-Path $HeapRoot $SnapshotName)
    return [ordered]@{
        about_memory = $AboutMemory
        captured_at = (Get-Date).ToUniversalTime().ToString("o")
        elapsed_seconds = [math]::Round(((Get-Date) - $BaselineAt).TotalSeconds, 3)
        heap_snapshot = $Snapshot
        label = $Label
        tab_heap_total_bytes = $TotalBytes
    }
}

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
    $BootstrapPython = $null
    $BootstrapArguments = @()
}

$Server = $null
$ManualFirefox = $null
$LocationPushed = $false
$CampaignRows = @()
$CampaignExitCode = 0
$CampaignFailure = $null
$CleanupFailure = $null
$FirefoxHeap = $null

try {
    Push-Location $ProjectRoot
    $LocationPushed = $true
    if (-not $BootstrapPython) {
        throw "Python 3.11 or newer was not found (expected py.exe or python.exe)."
    }
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
        "-m", "pip", "install", "--disable-pip-version-check", "--require-hashes",
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
    Write-Host "Keep this unlocked hardware-accelerated desktop foregrounded at 100% scaling."
    Write-Host "Each browser/viewport uses a fresh profile. During Match, listen and press"
    Write-Host "physical standard-mapped A then B. Six rows take about 25-30 minutes."
    Write-Host ""

    foreach ($Browser in @("chrome", "firefox")) {
        foreach ($Viewport in @("960x540", "1280x720", "1920x1080")) {
            $StabilitySeconds = if ($Viewport -eq "960x540") { 600 } else { 0 }
            Read-Host (
                "Ready for $Browser $Viewport with audible speakers and the physical " +
                "controller connected? Press Enter"
            ) | Out-Null

            $RowRoot = Join-Path $PacketRoot "$Browser-$Viewport"
            if (Test-Path -LiteralPath $RowRoot) {
                throw "Refusing reused row output: $RowRoot"
            }
            $MatrixArguments = @(
                "scripts\browser_matrix.py",
                "--browser", $Browser,
                "--url", $BaseUrl,
                "--viewport", $Viewport,
                "--flow-timeout", "300",
                "--stability-seconds", "$StabilitySeconds",
                "--require-gamepad",
                "--output", $RowRoot
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
            $Packet = Get-OnlyPacket $RowRoot
            $AudioHeard = Read-Decision "Was Galactic Cup audio audible during $Browser $Viewport?"
            $PhysicalButtons = Read-Decision (
                "Did you press physical standard-mapped A then B during Match in " +
                "$Browser $Viewport?"
            )
            $OperatorPass = $AudioHeard -eq "yes" -and $PhysicalButtons -eq "yes"
            $RowPass = $MatrixExitCode -eq 0 -and $OperatorPass
            if (-not $RowPass) {
                $CampaignExitCode = 1
            }
            $OperatorPath = Join-Path $Packet.FullName "operator-observation.json"
            Write-JsonFile $OperatorPath ([ordered]@{
                audio_audible = $AudioHeard
                browser = $Browser
                captured_at = (Get-Date).ToUniversalTime().ToString("o")
                pass = $OperatorPass
                physical_standard_mapped_a_then_b = $PhysicalButtons
                viewport = $Viewport
            })
            $CampaignRows += [ordered]@{
                archive = $null
                archive_sha256 = $null
                browser = $Browser
                matrix_exit_code = $MatrixExitCode
                operator_audio_audible = $AudioHeard
                operator_physical_a_then_b = $PhysicalButtons
                packet = $Packet.FullName
                pass = $RowPass
                stability_seconds = $StabilitySeconds
                viewport = $Viewport
            }
            Write-Host "Raw packet: $($Packet.FullName)"
        }
    }

    $FirefoxLongRow = $CampaignRows |
        Where-Object { $_.browser -eq "firefox" -and $_.viewport -eq "960x540" } |
        Select-Object -First 1
    if (-not $FirefoxLongRow) {
        throw "The Firefox 960x540 packet is required before heap capture."
    }
    $FirefoxEnvironmentPath = Join-Path $FirefoxLongRow.packet "environment.json"
    $FirefoxEnvironment = Get-Content -Raw -LiteralPath $FirefoxEnvironmentPath |
        ConvertFrom-Json
    $FirefoxBinaryPath = [string]$FirefoxEnvironment.browser_binary.path
    if (-not (Test-Path -LiteralPath $FirefoxBinaryPath -PathType Leaf)) {
        throw "Firefox packet did not retain a usable browser binary path."
    }
    $HeapRoot = Join-Path $FirefoxLongRow.packet "firefox-heap-companion"
    New-Item -ItemType Directory -Path $HeapRoot | Out-Null
    $HeapProfile = Join-Path $OutputRoot "firefox-heap-profile"
    New-Item -ItemType Directory -Path $HeapProfile | Out-Null
    $FlowArgument = [uri]::EscapeDataString('["--compat-flow"]')
    $HeapUrl = "${BaseUrl}?arg=$FlowArgument"

    Write-Host ""
    Write-Host "FIREFOX TAB-HEAP COMPANION"
    Write-Host "The server remains live. A new clean Firefox profile will open the exact artifact."
    Write-Host "Click the canvas once, let the flow reach stable Result, then open that tab's"
    Write-Host "DevTools Memory panel in Aggregate view. Do not use process RSS or snapshot file size."
    $ManualFirefox = Start-Process -FilePath $FirefoxBinaryPath -ArgumentList @(
        "-no-remote", "-profile", $HeapProfile, $HeapUrl
    ) -PassThru
    Read-Host "Press Enter when Result is stable and the Memory panel is ready" | Out-Null

    $BaselineAt = Get-Date
    $HeapCheckpoints = @()
    $HeapCheckpoints += Capture-FirefoxHeapCheckpoint $HeapRoot "t0" $BaselineAt
    Wait-ForCheckpoint ($BaselineAt.AddSeconds(300)) "t5"
    $HeapCheckpoints += Capture-FirefoxHeapCheckpoint $HeapRoot "t5" $BaselineAt
    Wait-ForCheckpoint ($BaselineAt.AddSeconds(600)) "t10"
    $HeapCheckpoints += Capture-FirefoxHeapCheckpoint $HeapRoot "t10" $BaselineAt

    $T0 = [double]$HeapCheckpoints[0].tab_heap_total_bytes
    $T5 = [double]$HeapCheckpoints[1].tab_heap_total_bytes
    $T10 = [double]$HeapCheckpoints[2].tab_heap_total_bytes
    $GrowthPercent = (($T10 - $T0) / $T0) * 100
    $MonotonicNonDecreasing = $T0 -le $T5 -and $T5 -le $T10
    $HeapPass = $GrowthPercent -le 25
    if (-not $HeapPass) {
        $CampaignExitCode = 1
    }
    $Manifest = Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot "build\web\manifest.json") |
        ConvertFrom-Json
    $FirefoxHeap = [ordered]@{
        browser_binary = $FirefoxEnvironment.browser_binary
        browser_capabilities = (
            Get-Content -Raw -LiteralPath (Join-Path $FirefoxLongRow.packet "summary.json") |
                ConvertFrom-Json
        ).results[0].browser.capabilities
        captured_at = (Get-Date).ToUniversalTime().ToString("o")
        checkpoints = $HeapCheckpoints
        formula = "(t10 - t0) / t0 * 100"
        growth_percent = [math]::Round($GrowthPercent, 6)
        manifest_sha256 = (
            Get-FileHash -Algorithm SHA256 -LiteralPath (
                Join-Path $ProjectRoot "build\web\manifest.json"
            )
        ).Hash.ToLowerInvariant()
        monotonic_non_decreasing = $MonotonicNonDecreasing
        package_sha256 = [string]($Manifest.game_package.sha256)
        pass = $HeapPass
        source_revision = [string]($Manifest.source_revision)
        threshold_percent = 25
        whole_tab_metric = "Firefox DevTools Memory Aggregate whole-heap Total Bytes"
    }
    Write-JsonFile (Join-Path $HeapRoot "firefox-heap-summary.json") $FirefoxHeap

    foreach ($Row in $CampaignRows) {
        $Packet = Get-Item -LiteralPath $Row.packet
        $Archive = Join-Path $ArchiveRoot "$($Packet.Name).zip"
        Compress-Archive -Path (Join-Path $Packet.FullName "*") -DestinationPath $Archive
        $ArchiveHashRecord = Get-FileHash -Algorithm SHA256 -LiteralPath $Archive
        $ArchiveHash = $ArchiveHashRecord.Hash.ToLowerInvariant()
        $Row.archive = $Archive
        $Row.archive_sha256 = $ArchiveHash
        Write-Host "Archive: $Archive"
        Write-Host "Archive SHA-256: $ArchiveHash"
    }
} catch {
    $CampaignExitCode = 1
    $CampaignFailure = [ordered]@{
        message = $_.Exception.Message
        script_stack_trace = $_.ScriptStackTrace
        type = $_.Exception.GetType().FullName
    }
} finally {
    if ($ManualFirefox -and -not $ManualFirefox.HasExited) {
        $null = $ManualFirefox.CloseMainWindow()
        if (-not $ManualFirefox.WaitForExit(10000)) {
            Stop-Process -Id $ManualFirefox.Id -ErrorAction SilentlyContinue
        }
    }
    if ($Server -and -not $Server.HasExited) {
        Stop-Process -Id $Server.Id -ErrorAction SilentlyContinue
        if (-not $Server.WaitForExit(10000)) {
            $CampaignExitCode = 1
            $CleanupFailure = "Artifact server did not exit within 10 seconds."
        }
    }
    if ($LocationPushed) {
        Pop-Location
    }
    $ExpectedRows = 6
    $CampaignComplete = (
        $CampaignExitCode -eq 0 -and
        $null -eq $CampaignFailure -and
        $null -eq $CleanupFailure -and
        $CampaignRows.Count -eq $ExpectedRows -and
        $null -ne $FirefoxHeap -and
        $FirefoxHeap.pass -eq $true
    )
    if (-not $CampaignComplete) {
        $CampaignExitCode = 1
    }
    Write-JsonFile $SummaryPath ([ordered]@{
        captured_at = (Get-Date).ToUniversalTime().ToString("o")
        cleanup_failure = $CleanupFailure
        complete = $CampaignComplete
        failure = $CampaignFailure
        firefox_heap = $FirefoxHeap
        output_root = $OutputRoot
        requirements_lock = Get-FileEvidence (
            Join-Path $ProjectRoot "scripts\browser_matrix-requirements.txt"
        )
        rows = $CampaignRows
        selenium_cache = $SeleniumCache
        server_stopped = ($null -eq $Server -or $Server.HasExited)
    })
}

Write-Host ""
Write-Host "Campaign summary: $SummaryPath"
Write-Host "Raw packets: $PacketRoot"
Write-Host "Archives: $ArchiveRoot"
if ($CampaignExitCode -ne 0) {
    Write-Warning (
        "The campaign is incomplete. A failed/unsure operator answer, missing heap/GPU " +
        "evidence, matrix failure, or cleanup failure must not be inferred as a pass."
    )
}
exit $CampaignExitCode
