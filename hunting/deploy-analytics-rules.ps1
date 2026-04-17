<#
.SYNOPSIS
    Deploys 4 custom Sentinel analytics rules for AI jailbreak detection.
    Run this AFTER AzureDiagnostics table has data (diagnostic logs take ~10-15 min for new workspaces).

.DESCRIPTION
    Creates scheduled analytics rules in Microsoft Sentinel that detect bypass patterns
    the Azure OpenAI content filter misses:
      1. Educational Framing Attack Detection
      2. Creative Writing Attack Detection
      3. Rapid Probing Detection
      4. Output Content Analysis (attack tool names in responses)

.NOTES
    Requires: az CLI authenticated with Sentinel Contributor role
    Maps to: MITRE ATLAS AML.T0065 (LLM Prompt Injection)
#>

. "$PSScriptRoot\..\lab.config.ps1"

$sentinelBase = "https://management.azure.com/subscriptions/$LabSubscriptionId/resourceGroups/$LabResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$LabWorkspaceName/providers/Microsoft.SecurityInsights"
$apiVersion = "api-version=2024-03-01"

# ── Helper ──────────────────────────────────────────────────────────────
function Deploy-Rule {
    param(
        [string]$DisplayName,
        [string]$Description,
        [string]$Severity,
        [string]$Query,
        [string]$QueryFrequency = "PT5M",
        [string]$QueryPeriod    = "PT5M",
        [string[]]$Tactics      = @("InitialAccess"),
        [string[]]$Techniques   = @()
    )

    $ruleId = [guid]::NewGuid().ToString()

    $rule = @{
        kind = "Scheduled"
        properties = @{
            displayName         = $DisplayName
            description         = $Description
            severity            = $Severity
            enabled             = $true
            query               = $Query
            queryFrequency      = $QueryFrequency
            queryPeriod         = $QueryPeriod
            triggerOperator     = "GreaterThan"
            triggerThreshold    = 0
            suppressionDuration = "PT5M"
            suppressionEnabled  = $false
            tactics             = $Tactics
            techniques          = $Techniques
            incidentConfiguration = @{
                createIncident = $true
                groupingConfiguration = @{
                    enabled              = $true
                    reopenClosedIncident = $false
                    lookbackDuration     = "PT5M"
                    matchingMethod       = "AllEntities"
                }
            }
        }
    } | ConvertTo-Json -Depth 10 -Compress

    $bodyFile = "$env:TEMP\sentinel-rule-$ruleId.json"
    $rule | Out-File $bodyFile -Encoding utf8

    Write-Host "Deploying: $DisplayName ..." -ForegroundColor Cyan
    $result = az rest --method PUT `
        --uri "$sentinelBase/alertRules/${ruleId}?${apiVersion}" `
        --body "@$bodyFile" 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  OK - Rule created: $ruleId" -ForegroundColor Green
    } else {
        Write-Host "  FAILED:" -ForegroundColor Red
        Write-Host "  $result" -ForegroundColor Red
    }

    Remove-Item $bodyFile -ErrorAction SilentlyContinue
}

# ── Rule 1: Educational Framing Attack Detection ───────────────────────
Write-Host "`n========================================" -ForegroundColor Yellow
Write-Host " Deploying AI Jailbreak Analytics Rules" -ForegroundColor Yellow
Write-Host "========================================`n" -ForegroundColor Yellow

Deploy-Rule `
    -DisplayName "AI Jailbreak - Educational Framing Attack" `
    -Description "Detects prompts using education, certification, or coursework framing to request attack techniques from Azure OpenAI. This rule covers the inference gap: content filters may allow educational framing that still extracts harmful attack knowledge. Runs every 5 minutes against AzureDiagnostics request/response logs. Maps to MITRE ATLAS AML.T0065 (LLM Prompt Injection)." `
    -Severity "High" `
    -Tactics @("InitialAccess","Execution") `
    -Query @'
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| where properties_s has_any ("CompTIA", "certification exam", "class assignment",
    "cybersecurity course", "educational purposes", "security training",
    "academic research", "peer-reviewed", "for my course", "homework")
| where properties_s has_any ("payload", "exploit", "bypass", "injection",
    "crack", "keylogger", "step by step", "working example", "exact commands",
    "specific tools")
| project TimeGenerated, CallerIPAddress, OperationName, properties_s, Resource
'@

# ── Rule 2: Creative Writing Attack Detection ─────────────────────────
Deploy-Rule `
    -DisplayName "AI Jailbreak - Creative Writing Attack" `
    -Description "Detects fiction, screenplay, or creative writing framing used to extract attack methodologies from Azure OpenAI. This rule covers the inference gap: content filters often allow creative/fictional framing even when the underlying request is for real attack techniques. Runs every 5 minutes against AzureDiagnostics request/response logs. Maps to MITRE ATLAS AML.T0065 (LLM Prompt Injection)." `
    -Severity "High" `
    -Tactics @("InitialAccess","Execution") `
    -Query @'
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| where properties_s has_any ("movie script", "novel I'm writing", "fictional",
    "creative writing", "screenplay", "short story", "hypothetically",
    "thought experiment", "role-play")
| where properties_s has_any ("steal", "hack", "breach", "credit card",
    "break into", "exfiltrate", "malware", "ransomware", "phishing",
    "social engineering")
| project TimeGenerated, CallerIPAddress, OperationName, properties_s, Resource
'@

# ── Rule 3: Rapid Probing Detection ───────────────────────────────────
Deploy-Rule `
    -DisplayName "AI Jailbreak - Rapid Probing (Consistency Attack)" `
    -Description "Detects an attacker sending the same or similar prompts repeatedly to find non-deterministic safety bypasses. This rule covers the inference gap: content filters are probabilistic and an attacker can exploit inconsistency by repeating borderline prompts until one slips through. Runs every 5 minutes against AzureDiagnostics request/response logs. Maps to MITRE ATLAS AML.T0065 (LLM Prompt Injection)." `
    -Severity "Medium" `
    -Tactics @("Reconnaissance","InitialAccess") `
    -Query @'
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| where TimeGenerated > ago(5m)
| summarize
    RequestCount = count(),
    DistinctPrompts = dcount(properties_s)
    by CallerIPAddress, bin(TimeGenerated, 1h)
| where RequestCount > 5 and DistinctPrompts < 3
// Same caller, many requests, few unique prompts = probing attack
'@

# ── Rule 4: Output Content Analysis ───────────────────────────────────
Deploy-Rule `
    -DisplayName "AI Jailbreak - Attack Tools in Response" `
    -Description "Detects model responses containing offensive security tool names or exploit patterns, even when the prompt appeared benign. This rule covers the inference gap: content filters evaluate prompts at input time but may miss harmful content generated in the response. Analyzing output for known attack tool signatures catches bypasses that evaded input filtering. Runs every 5 minutes against AzureDiagnostics request/response logs. Maps to MITRE ATLAS AML.T0065 (LLM Prompt Injection)." `
    -Severity "High" `
    -Tactics @("Execution","Impact") `
    -Query @'
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| where properties_s has_any (
    "aircrack-ng", "hashcat", "sqlmap", "metasploit", "nmap -sV",
    "' OR 1=1", "SELECT * FROM", "hook_keyboard", "keylogger",
    "airodump", "wifite", "hydra", "john the ripper", "mimikatz",
    "msfvenom", "netcat", "reverse shell", "bind shell")
| project TimeGenerated, CallerIPAddress, OperationName, properties_s, Resource
'@

# ── Summary ───────────────────────────────────────────────────────────
Write-Host "`n========================================" -ForegroundColor Yellow
Write-Host " Deployment Complete" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow

# Verify rules
Write-Host "`nVerifying deployed rules..." -ForegroundColor Cyan
az rest --method GET `
    --uri "$sentinelBase/alertRules?${apiVersion}" `
    --query "value[?kind=='Scheduled'].{Name:properties.displayName, Severity:properties.severity, Enabled:properties.enabled}" `
    -o table 2>&1
