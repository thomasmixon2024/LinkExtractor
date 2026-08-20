# ============================================
# LinkExtractor  Enterprise Core
# Version: 1.0.0
# Build Date: 2026-08-20
# ============================================

$Global:LinkExtractorVersion = "1.0.0"
$EnableAutoUpdate = $true

function Invoke-LinkExtractorUpdate {
    Write-Host "[INFO] Checking for updates..." -ForegroundColor Cyan

    $repo = "thomasmixon2024/LinkExtractor"
    $apiUrl = "https://api.github.com/repos/$repo/contents/LinkExtractor.ps1"

    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Headers @{ "User-Agent" = "LinkExtractor" }
        $remoteContent = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($response.content))
        $localContent = Get-Content -Path $PSCommandPath -Raw

        if ($remoteContent -ne $localContent) {
            Write-Host "[UPDATE] New version detected. Applying update..." -ForegroundColor Yellow
            Set-Content -Path $PSCommandPath -Value $remoteContent -Force
            Write-Host "[UPDATE] Update complete. Restarting..." -ForegroundColor Green
            Start-Process pwsh -ArgumentList $PSCommandPath
            exit
        } else {
            Write-Host "[INFO] Already up to date." -ForegroundColor Green
        }
    }
    catch {
        Write-Host "[ERROR] Update check failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

if ($EnableAutoUpdate) {
    Invoke-LinkExtractorUpdate
}

Write-Host "============================================" -ForegroundColor Green
Write-Host " LinkExtractor Core v$Global:LinkExtractorVersion Ready" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
