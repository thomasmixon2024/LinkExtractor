<#
==============================================================================
Link Extractor (Enterprise-Grade PowerShell Pipeline - A+ Release)
Rebuilt to standing PowerShell/Python coding protocol:
  - Directory enforcement (first action, every run)
  - Continuous bug sweep / defensive error handling
  - Full logging + performance analytics to Logs\ folder
  - Colored Success/Failure + purple suggestions + brighter-purple resolution
==============================================================================
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory=$false, Position=0)]
    [string]$TargetUrl,

    [Parameter(Mandatory=$false)]
    [ValidateSet("BestMP4", "BestAvailable", "AudioOnly")]
    [string]$QualityPreset = "BestMP4",

    [Parameter(Mandatory=$false)]
    [string]$BatchFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ==============================================================================
# 0. ROOT PATHS  (edit $script:RootDir if you want this installed elsewhere)
# ==============================================================================
$script:RootDir         = Join-Path -Path $env:USERPROFILE -ChildPath "Documents\LinkExtractor"
$script:LogsDir          = Join-Path -Path $script:RootDir -ChildPath "Logs"
$script:IngestTargetDir  = Join-Path -Path $env:USERPROFILE -ChildPath "Videos\LinkExtractor"
$script:OutputTemplate   = Join-Path -Path $script:IngestTargetDir -ChildPath "%(title)s [%(id)s].%(ext)s"
$script:SessionStamp     = Get-Date -Format "yyyyMMdd_HHmmss"
$script:LogFile          = Join-Path -Path $script:LogsDir -ChildPath "LinkExtractor_$($script:SessionStamp).log"
$script:PerfLogFile      = Join-Path -Path $script:LogsDir -ChildPath "LinkExtractor_Performance_$($script:SessionStamp).csv"

# ==============================================================================
# 1. LOGGING + PERFORMANCE ANALYTICS
# ==============================================================================

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','SUCCESS','PERF')][string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] [$Level] $Message"

    try {
        Add-Content -Path $script:LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Host "LOG WRITE FAILURE: $_" -ForegroundColor Red
    }

    switch ($Level) {
        'ERROR'   { Write-Host $line -ForegroundColor Red }
        'WARN'    { Write-Host $line -ForegroundColor Yellow }
        'SUCCESS' { Write-Host $line -ForegroundColor Green }
        'PERF'    { Write-Host $line -ForegroundColor Cyan }
        default   { Write-Host $line -ForegroundColor Gray }
    }
}

function Write-PerfRecord {
    param(
        [string]$Operation,
        [string]$Target,
        [double]$ElapsedSeconds,
        [string]$Result,
        [double]$FileSizeMB = 0
    )

    try {
        if (-not (Test-Path -Path $script:PerfLogFile)) {
            "Timestamp,Operation,Target,ElapsedSeconds,Result,FileSizeMB" | Out-File -FilePath $script:PerfLogFile -Encoding UTF8
        }
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $safeTarget = $Target -replace ',', ';'
        "$ts,$Operation,$safeTarget,$([math]::Round($ElapsedSeconds,2)),$Result,$([math]::Round($FileSizeMB,2))" |
            Add-Content -Path $script:PerfLogFile -Encoding UTF8
    } catch {
        Write-Log -Level WARN -Message "Failed to write performance record: $_"
    }
}

function Invoke-TimedFunction {
    param(
        [Parameter(Mandatory=$true)][scriptblock]$ScriptBlock,
        [Parameter(Mandatory=$true)][string]$OperationName,
        [string]$Target = ""
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $result = $null
    $errorCaught = $null

    try {
        $result = & $ScriptBlock
    } catch {
        $errorCaught = $_
    } finally {
        $stopwatch.Stop()
    }

    $elapsed = $stopwatch.Elapsed.TotalSeconds
    Write-Log -Level PERF -Message "$OperationName completed in $([math]::Round($elapsed,2))s (Target: $Target)"

    if ($errorCaught) {
        Write-PerfRecord -Operation $OperationName -Target $Target -ElapsedSeconds $elapsed -Result "ERROR"
        throw $errorCaught
    }

    Write-PerfRecord -Operation $OperationName -Target $Target -ElapsedSeconds $elapsed -Result "OK"
    return $result
}

# ==============================================================================
# 2. DIRECTORY ENFORCEMENT (MANDATORY FIRST ACTION)
# ==============================================================================

function Confirm-WorkingEnvironment {
    Write-Host "[Directory Enforcement] Verifying required folder structure..." -ForegroundColor Yellow

    $requiredDirs = @($script:RootDir, $script:LogsDir, $script:IngestTargetDir)

    foreach ($dir in $requiredDirs) {
        if (-not (Test-Path -Path $dir -PathType Container)) {
            try {
                $null = New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop
            } catch {
                Write-Host "CRITICAL ERROR: Could not create required directory '$dir': $_" -ForegroundColor Red
                Write-Host "Suggested action: verify you have write permissions to '$env:USERPROFILE' and re-run." -ForegroundColor DarkMagenta
                exit 1
            }
        }
    }

    # Logging can only start once LogsDir is guaranteed to exist.
    Write-Log -Level INFO -Message "Directory enforcement passed. RootDir='$($script:RootDir)' LogsDir='$($script:LogsDir)' IngestDir='$($script:IngestTargetDir)'"

    try {
        Set-Location -Path $script:RootDir -ErrorAction Stop
        Write-Log -Level INFO -Message "Working directory confirmed: $((Get-Location).Path)"
    } catch {
        Write-Host "CRITICAL ERROR: Failed to switch to required working directory '$($script:RootDir)': $_" -ForegroundColor Red
        exit 1
    }
}

# ==============================================================================
# 3. UI / DIAGNOSTIC HELPERS
# ==============================================================================

function Show-Header {
    # Clear-Host throws in some non-interactive / redirected hosts - guard it.
    try { Clear-Host } catch { }
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "     LINK EXTRACTOR (ENTERPRISE CORE - A+ BUILD)    " -ForegroundColor White
    Write-Host "==================================================" -ForegroundColor Cyan
}

function Wait-ForInput {
    param([string]$PromptMessage = "Press Enter to return to menu...")
    Write-Host "`n$PromptMessage" -ForegroundColor Gray
    try {
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } catch {
        $null = Read-Host
    }
}

function Show-FinalStatus {
    param(
        [Parameter(Mandatory=$true)][bool]$Success,
        [string]$Context = "Operation"
    )

    Write-Host ""
    if ($Success) {
        Write-Host "STATUS: SUCCESS - $Context completed cleanly." -ForegroundColor Green
        Write-Log -Level SUCCESS -Message "$Context completed cleanly."
    } else {
        Write-Host "STATUS: FAILURE - $Context did not complete successfully." -ForegroundColor Red
        Write-Log -Level ERROR -Message "$Context did not complete successfully."
    }

    Write-Host "SUGGESTED NEXT ACTIONS:" -ForegroundColor DarkMagenta
    if ($Success) {
        Write-Host "  - Review the output file(s) in: $($script:IngestTargetDir)" -ForegroundColor DarkMagenta
        Write-Host "  - Review full run log at: $($script:LogFile)" -ForegroundColor DarkMagenta
    } else {
        Write-Host "  - Review the error detail in: $($script:LogFile)" -ForegroundColor DarkMagenta
        Write-Host "  - Confirm yt-dlp and ffmpeg are installed and on PATH" -ForegroundColor DarkMagenta
        Write-Host "  - Re-run the failing item individually to isolate the cause" -ForegroundColor DarkMagenta
    }

    Write-Host "READY-TO-RUN RESOLUTION:" -ForegroundColor Magenta
    if ($Success) {
        Write-Host '  Invoke-Item "' + $script:IngestTargetDir + '"' -ForegroundColor Magenta
    } else {
        Write-Host '  Get-Content "' + $script:LogFile + '" -Tail 40' -ForegroundColor Magenta
    }
}

function Test-FastNetworkConnection {
    if (-not [System.Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()) {
        return $false
    }

    $tcpClient = [System.Net.Sockets.TcpClient]::new()
    try {
        $asyncResult = $tcpClient.BeginConnect("8.8.8.8", 80, $null, $null)
        $waitHandle = $asyncResult.AsyncWaitHandle.WaitOne(250, $false)

        if ($waitHandle) {
            $tcpClient.EndConnect($asyncResult)
            return $true
        }
        return $false
    } catch {
        return $false
    } finally {
        $tcpClient.Dispose()
    }
}

function Test-Prerequisites {
    Write-Log -Level INFO -Message "Running pre-flight dependency checks."

    $ytDlpCmd = Get-Command "yt-dlp" -ErrorAction SilentlyContinue
    if (-not $ytDlpCmd) {
        Write-Log -Level ERROR -Message "'yt-dlp' binary not found in system PATH."
        Show-FinalStatus -Success $false -Context "Pre-flight dependency check"
        exit 1
    }

    $ffmpegCmd = Get-Command "ffmpeg" -ErrorAction SilentlyContinue
    if (-not $ffmpegCmd) {
        Write-Log -Level ERROR -Message "'ffmpeg' binary not found in system PATH. Required for merge/thumbnail embed/mp3 conversion."
        Show-FinalStatus -Success $false -Context "Pre-flight dependency check"
        exit 1
    }

    if (-not (Test-FastNetworkConnection)) {
        Write-Log -Level WARN -Message "Network pre-flight check timed out or interface is offline."
    } else {
        Write-Log -Level INFO -Message "Network connectivity confirmed."
    }

    Write-Log -Level INFO -Message "Pre-flight checks passed (yt-dlp + ffmpeg present)."
}

# ==============================================================================
# 4. CORE EXTRACTION LOGIC
# ==============================================================================

function Get-OptimizedFormatArgs {
    param([string]$Preset)

    switch ($Preset) {
        "BestMP4" {
            return [string[]]@(
                "-f", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
                "--merge-output-format", "mp4"
            )
        }
        "BestAvailable" {
            return [string[]]@(
                "-f", "bestvideo+bestaudio/best"
            )
        }
        "AudioOnly" {
            return [string[]]@(
                "-x",
                "--audio-format", "mp3",
                "--audio-quality", "0"
            )
        }
        default {
            Write-Log -Level ERROR -Message "Unknown quality preset requested: '$Preset'"
            return $null
        }
    }
}

function Start-Extraction {
    param(
        [string]$Url,
        [string]$Preset = "BestMP4"
    )

    $uriResult = $null
    $validUri = [System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$uriResult) -and
                ($uriResult.Scheme -eq 'http' -or $uriResult.Scheme -eq 'https')

    if (-not $validUri) {
        Write-Log -Level ERROR -Message "Target '$Url' must be a valid HTTP or HTTPS URI."
        return $false
    }

    $formatArgs = Get-OptimizedFormatArgs -Preset $Preset
    if ($null -eq $formatArgs) {
        Write-Log -Level ERROR -Message "Aborting extraction for '$Url' - invalid preset resolved no format args."
        return $false
    }

    Write-Log -Level INFO -Message "Extraction starting. URL='$Url' Preset='$Preset'"

    [string[]]$performanceArgs = @(
        "--concurrent-fragments", "4",
        "--buffer-size", "64k",
        "--no-mtime"
    )

    [string[]]$baseArgs = @(
        "-o", $script:OutputTemplate,
        "--no-playlist",
        "--continue",
        "--embed-metadata",
        "--embed-thumbnail",
        "--print", "after_move:FINALPATH::%(filepath)s"
    )

    [string[]]$finalArgs = [string[]]($formatArgs + $performanceArgs + $baseArgs + @($Url))

    $previousDir = Get-Location
    Set-Location -Path $script:IngestTargetDir
    $ytdlpOutput = @()
    $exitCode = -1

    try {
        $ytdlpOutput = & yt-dlp $finalArgs 2>&1
        $exitCode = $LASTEXITCODE
        $ytdlpOutput | ForEach-Object { Write-Host $_ }
    } catch {
        Write-Log -Level ERROR -Message "Unhandled exception during yt-dlp invocation for '$Url': $_"
        $exitCode = -1
    } finally {
        Set-Location -Path $previousDir
    }

    Write-Host "----------------------------------------"

    if ($exitCode -eq 0) {
        # Recover the exact output file via the FINALPATH marker instead of guessing
        # by "most recently modified file in the folder" (unreliable under batch runs).
        $finalPathLine = $ytdlpOutput | Where-Object { $_ -match '^FINALPATH::' } | Select-Object -Last 1

        if ($finalPathLine) {
            $actualFile = ($finalPathLine -replace '^FINALPATH::', '').Trim()
            Write-Log -Level SUCCESS -Message "Extraction succeeded for '$Url'. Output: $actualFile"

            if (Test-Path -Path $actualFile -PathType Leaf) {
                $fileInfo = Get-Item -Path $actualFile
                Write-Host "File Name : $($fileInfo.Name)" -ForegroundColor Green
                Write-Host "File Size : $([math]::Round($fileInfo.Length / 1MB, 2)) MB" -ForegroundColor Green
            }
        } else {
            Write-Log -Level WARN -Message "Extraction reported success for '$Url' but FINALPATH marker was not found in output."
        }

        return $true
    } else {
        Write-Log -Level ERROR -Message "Extraction failed for '$Url'. yt-dlp exit code: $exitCode"
        return $false
    }
}

function Start-BatchExtraction {
    param(
        [string]$FilePath,
        [string]$Preset = "BestMP4"
    )

    if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
        Write-Log -Level ERROR -Message "Batch file not found at path '$FilePath'."
        return $false
    }

    [string[]]$rawUrls = @()
    try {
        $lines = [System.IO.File]::ReadLines($FilePath)
        foreach ($line in $lines) {
            $trimmed = $line.Trim()
            if (-not [string]::IsNullOrWhiteSpace($trimmed) -and -not $trimmed.StartsWith("#")) {
                $rawUrls += $trimmed
            }
        }
    } catch {
        Write-Log -Level ERROR -Message "Unable to read batch file '$FilePath': $_"
        return $false
    }

    # De-duplicate while preserving original order.
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    [string[]]$urls = foreach ($u in $rawUrls) {
        if ($seen.Add($u)) { $u }
    }

    $duplicateCount = $rawUrls.Count - $urls.Count
    if ($duplicateCount -gt 0) {
        Write-Log -Level WARN -Message "Removed $duplicateCount duplicate URL(s) from batch file."
    }

    $totalCount = $urls.Count
    if ($totalCount -eq 0) {
        Write-Log -Level WARN -Message "No valid URLs found in file '$FilePath'."
        return $false
    }

    Write-Host "`n========== STARTING BATCH PROCESSING ==========" -ForegroundColor Cyan
    Write-Host "Batch File : $FilePath"
    Write-Host "Queue Size : $totalCount item(s) (Preset: $Preset)"
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Log -Level INFO -Message "Batch processing started. File='$FilePath' Count=$totalCount Preset='$Preset'"

    $successCount = 0
    $failureCount = 0

    for ($i = 0; $i -lt $totalCount; $i++) {
        $currentUrl = $urls[$i]
        $currentIndex = $i + 1

        Write-Host "`n[$currentIndex/$totalCount] Item Processing: $currentUrl" -ForegroundColor Cyan
        $result = Invoke-TimedFunction -OperationName "Start-Extraction" -Target $currentUrl -ScriptBlock {
            Start-Extraction -Url $currentUrl -Preset $Preset
        }

        if ($result) { $successCount++ } else { $failureCount++ }
    }

    $summaryColor = "Green"
    if ($failureCount -gt 0) { $summaryColor = "Red" }

    Write-Host "`n========== BATCH PROCESSING COMPLETE ==========" -ForegroundColor Green
    Write-Host "Total Processed : $totalCount"
    Write-Host "Successful      : $successCount" -ForegroundColor Green
    Write-Host "Failed          : $failureCount" -ForegroundColor $summaryColor
    Write-Host "===============================================" -ForegroundColor Green
    Write-Log -Level INFO -Message "Batch processing complete. Total=$totalCount Success=$successCount Failed=$failureCount"

    return ($failureCount -eq 0)
}

# ==============================================================================
# 5. EXECUTION ENTRY POINT
# ==============================================================================

Confirm-WorkingEnvironment
Show-Header
Test-Prerequisites

# Unattended Batch Mode
if ($PSBoundParameters.ContainsKey("BatchFile") -and -not [string]::IsNullOrWhiteSpace($BatchFile)) {
    $success = Invoke-TimedFunction -OperationName "Start-BatchExtraction" -Target $BatchFile -ScriptBlock {
        Start-BatchExtraction -FilePath $BatchFile -Preset $QualityPreset
    }
    Show-FinalStatus -Success $success -Context "Batch extraction ($BatchFile)"
    if ($success) { exit 0 } else { exit 1 }
}

# Unattended Single URL Mode
if ($PSBoundParameters.ContainsKey("TargetUrl") -and -not [string]::IsNullOrWhiteSpace($TargetUrl)) {
    $success = Invoke-TimedFunction -OperationName "Start-Extraction" -Target $TargetUrl -ScriptBlock {
        Start-Extraction -Url $TargetUrl -Preset $QualityPreset
    }
    Show-FinalStatus -Success $success -Context "Single URL extraction ($TargetUrl)"
    if ($success) { exit 0 } else { exit 1 }
}

# Interactive CLI Loop
do {
    Show-Header
    Write-Host " Select Option:" -ForegroundColor White
    Write-Host ""
    Write-Host "  [1] Extract Video (MP4 - Best Compatibility)"
    Write-Host "  [2] Extract Video (Highest Raw Quality)"
    Write-Host "  [3] Extract Audio Only (MP3)"
    Write-Host "  [4] Process Batch List (.txt file)"
    Write-Host "  [5] Open Target Folder in Explorer"
    Write-Host "  [6] Check Core Engine Version"
    Write-Host "  [7] Open Logs Folder"
    Write-Host "  [Q] Exit"
    Write-Host ""

    $selection = Read-Host "Select option [1-7 or Q]"

    switch ($selection.ToUpper()) {
        "1" {
            $inputUrl = Read-Host "`nPaste target media URL"
            $result = Invoke-TimedFunction -OperationName "Start-Extraction" -Target $inputUrl -ScriptBlock {
                Start-Extraction -Url $inputUrl -Preset "BestMP4"
            }
            Show-FinalStatus -Success $result -Context "Extraction ($inputUrl)"
            Wait-ForInput
        }
        "2" {
            $inputUrl = Read-Host "`nPaste target media URL"
            $result = Invoke-TimedFunction -OperationName "Start-Extraction" -Target $inputUrl -ScriptBlock {
                Start-Extraction -Url $inputUrl -Preset "BestAvailable"
            }
            Show-FinalStatus -Success $result -Context "Extraction ($inputUrl)"
            Wait-ForInput
        }
        "3" {
            $inputUrl = Read-Host "`nPaste target media URL"
            $result = Invoke-TimedFunction -OperationName "Start-Extraction" -Target $inputUrl -ScriptBlock {
                Start-Extraction -Url $inputUrl -Preset "AudioOnly"
            }
            Show-FinalStatus -Success $result -Context "Extraction ($inputUrl)"
            Wait-ForInput
        }
        "4" {
            $filePath = Read-Host "`nEnter full path to text file containing URLs"
            $presetChoice = Read-Host "Select Preset ([1] BestMP4, [2] BestAvailable, [3] AudioOnly) [Default: 1]"

            $chosenPreset = switch ($presetChoice) {
                "2" { "BestAvailable" }
                "3" { "AudioOnly" }
                default { "BestMP4" }
            }

            $result = Invoke-TimedFunction -OperationName "Start-BatchExtraction" -Target $filePath -ScriptBlock {
                Start-BatchExtraction -FilePath $filePath -Preset $chosenPreset
            }
            Show-FinalStatus -Success $result -Context "Batch extraction ($filePath)"
            Wait-ForInput
        }
        "5" {
            Invoke-Item -Path $script:IngestTargetDir
            Write-Host "`nOpened '$($script:IngestTargetDir)'." -ForegroundColor Green
            Start-Sleep -Seconds 2
        }
        "6" {
            Write-Host "`nQuerying Engine Version..." -ForegroundColor Yellow
            try {
                & yt-dlp --version
            } catch {
                Write-Log -Level ERROR -Message "Engine version query failed: $_"
            }
            Wait-ForInput
        }
        "7" {
            Invoke-Item -Path $script:LogsDir
            Write-Host "`nOpened '$($script:LogsDir)'." -ForegroundColor Green
            Start-Sleep -Seconds 2
        }
        "Q" {
            Write-Log -Level INFO -Message "Session ended by user."
            Write-Host "`nExiting system." -ForegroundColor Cyan
            exit 0
        }
        default {
            Write-Host "`nInvalid selection." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
} while ($true)
