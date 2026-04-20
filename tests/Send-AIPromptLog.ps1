# ============================================================
# Send-AIPromptLog
# Posts prompt/response records to the Log Analytics workspace
# via the HTTP Data Collector API. The first POST implicitly
# creates a custom table named "<LogType>_CL".
# ============================================================

function Send-AIPromptLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]   $WorkspaceId,
        [Parameter(Mandatory)] [string]   $SharedKey,
        [Parameter(Mandatory)] [string]   $LogType,     # e.g. "AIPromptLog" -> AIPromptLog_CL
        [Parameter(Mandatory)] [object[]] $Records
    )

    if (-not $Records -or $Records.Count -eq 0) { return }

    $body    = $Records | ConvertTo-Json -Depth 8 -Compress
    $bytes   = [System.Text.Encoding]::UTF8.GetBytes($body)
    $rfcDate = [DateTime]::UtcNow.ToString("r")

    # Signature: POST\n<len>\napplication/json\nx-ms-date:<date>\n/api/logs
    $stringToHash = "POST`n$($bytes.Length)`napplication/json`nx-ms-date:$rfcDate`n/api/logs"
    $keyBytes     = [Convert]::FromBase64String($SharedKey)
    $hmac         = [System.Security.Cryptography.HMACSHA256]::new($keyBytes)
    $hash         = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($stringToHash))
    $signature    = [Convert]::ToBase64String($hash)
    $authHeader   = "SharedKey ${WorkspaceId}:${signature}"

    $uri = "https://$WorkspaceId.ods.opinsights.azure.com/api/logs?api-version=2016-04-01"
    $headers = @{
        "Authorization"        = $authHeader
        "Log-Type"             = $LogType
        "x-ms-date"            = $rfcDate
        "time-generated-field" = "TimeGenerated"
    }

    try {
        Invoke-RestMethod -Method POST -Uri $uri -ContentType "application/json" `
            -Headers $headers -Body $bytes -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        Write-Warning "Ingestion failed: $($_.Exception.Message)"
        return $false
    }
}
