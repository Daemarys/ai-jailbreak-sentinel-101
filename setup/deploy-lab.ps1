# ============================================================
# AI Jailbreak Lab - Environment Setup & Validation
# ============================================================
# Run this FIRST when setting up the lab in a new tenant.
# It authenticates, validates resources, and confirms readiness.
#
# Usage:
#   .\setup\deploy-lab.ps1
# ============================================================

param(
    [switch]$SkipDeploy   # Skip resource creation, only validate
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  AI Jailbreak Lab - Environment Setup" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

# -----------------------------------------------------------
# Step 0: Load or create config
# -----------------------------------------------------------
$configPath = Join-Path $PSScriptRoot "..\lab.config.ps1"
$examplePath = Join-Path $PSScriptRoot "..\lab.config.example.ps1"

if (-not (Test-Path $configPath)) {
    Write-Host "[!] lab.config.ps1 not found." -ForegroundColor Yellow
    Write-Host "    Creating from template..." -ForegroundColor Yellow
    Copy-Item $examplePath $configPath
    Write-Host ""
    Write-Host "ACTION REQUIRED:" -ForegroundColor Red
    Write-Host "  1. Open lab.config.ps1" -ForegroundColor Red
    Write-Host "  2. Fill in your Azure tenant and resource values" -ForegroundColor Red
    Write-Host "  3. Re-run this script" -ForegroundColor Red
    Write-Host ""
    exit 1
}

. $configPath

# Validate config is filled in
$placeholders = @($LabTenantId, $LabEndpoint, $LabDeploymentName, $LabAoaiResourceGroup, $LabSubscriptionId, $LabResourceGroup, $LabWorkspaceName)
$hasPlaceholder = $placeholders | Where-Object { $_ -match "^<" -or [string]::IsNullOrWhiteSpace($_) }
if ($hasPlaceholder) {
    Write-Host "[!] lab.config.ps1 still has placeholder values." -ForegroundColor Red
    Write-Host "    Edit the file and replace all <your-...> values." -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Configuration loaded from lab.config.ps1" -ForegroundColor Green
Write-Host "     Tenant:      $LabTenantId" -ForegroundColor Gray
Write-Host "     Endpoint:    $LabEndpoint" -ForegroundColor Gray
Write-Host "     Deployment:  $LabDeploymentName" -ForegroundColor Gray
Write-Host "     OpenAI RG:   $LabAoaiResourceGroup" -ForegroundColor Gray
Write-Host "     Workspace:   $LabWorkspaceName" -ForegroundColor Gray
Write-Host ""

# -----------------------------------------------------------
# Step 1: Authenticate to Azure
# -----------------------------------------------------------
Write-Host "--- Step 1: Azure Authentication ---" -ForegroundColor Yellow
Write-Host ""

$currentAccount = az account show 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
if ($currentAccount -and $currentAccount.tenantId -eq $LabTenantId) {
    Write-Host "[OK] Already logged in to tenant $LabTenantId" -ForegroundColor Green
    Write-Host "     Account: $($currentAccount.user.name)" -ForegroundColor Gray
} else {
    Write-Host "[*] Logging in to tenant $LabTenantId..." -ForegroundColor Gray
    az login --tenant $LabTenantId
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAIL] Login failed." -ForegroundColor Red
        exit 1
    }
    Write-Host "[OK] Logged in successfully." -ForegroundColor Green
}

# Set subscription
Write-Host "[*] Setting subscription $LabSubscriptionId..." -ForegroundColor Gray
az account set --subscription $LabSubscriptionId
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] Could not set subscription." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Subscription set." -ForegroundColor Green
Write-Host ""

# -----------------------------------------------------------
# Step 2: Validate Azure OpenAI resource
# -----------------------------------------------------------
Write-Host "--- Step 2: Azure OpenAI Validation ---" -ForegroundColor Yellow
Write-Host ""

# Extract resource name from endpoint
$aoaiName = ([uri]$LabEndpoint).Host.Split('.')[0]

$aoaiResource = az cognitiveservices account show `
    --name $aoaiName `
    --resource-group $LabAoaiResourceGroup 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue

if ($aoaiResource) {
    Write-Host "[OK] Azure OpenAI resource found: $aoaiName" -ForegroundColor Green
    Write-Host "     Location: $($aoaiResource.location)" -ForegroundColor Gray
    Write-Host "     Endpoint: $($aoaiResource.properties.endpoint)" -ForegroundColor Gray
} else {
    Write-Host "[FAIL] Azure OpenAI resource '$aoaiName' not found in RG '$LabAoaiResourceGroup'" -ForegroundColor Red
    Write-Host "       Create it first or check your lab.config.ps1 values." -ForegroundColor Red
    exit 1
}

# Check deployment
Write-Host "[*] Checking model deployment '$LabDeploymentName'..." -ForegroundColor Gray
$deployment = az cognitiveservices account deployment list `
    --name $aoaiName `
    --resource-group $LabAoaiResourceGroup 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue |
    Where-Object { $_.name -eq $LabDeploymentName }

if ($deployment) {
    Write-Host "[OK] Deployment found: $LabDeploymentName ($($deployment.properties.model.name))" -ForegroundColor Green
} else {
    Write-Host "[WARN] Deployment '$LabDeploymentName' not found." -ForegroundColor Yellow
    Write-Host "       Available deployments:" -ForegroundColor Yellow
    az cognitiveservices account deployment list --name $aoaiName --resource-group $LabAoaiResourceGroup --query "[].{Name:name, Model:properties.model.name}" -o table
}
Write-Host ""

# -----------------------------------------------------------
# Step 3: Validate Log Analytics / Sentinel
# -----------------------------------------------------------
Write-Host "--- Step 3: Sentinel Workspace Validation ---" -ForegroundColor Yellow
Write-Host ""

$workspace = az monitor log-analytics workspace show `
    --resource-group $LabResourceGroup `
    --workspace-name $LabWorkspaceName 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue

if ($workspace) {
    Write-Host "[OK] Log Analytics workspace found: $LabWorkspaceName" -ForegroundColor Green
    Write-Host "     Retention: $($workspace.retentionInDays) days" -ForegroundColor Gray
} else {
    Write-Host "[FAIL] Workspace '$LabWorkspaceName' not found." -ForegroundColor Red
    exit 1
}

Write-Host ""

# -----------------------------------------------------------
# Step 4: Validate Diagnostic Settings
# -----------------------------------------------------------
Write-Host "--- Step 4: Diagnostic Logging Check ---" -ForegroundColor Yellow
Write-Host ""

$resourceId = $aoaiResource.id
$diagSettings = az monitor diagnostic-settings list --resource $resourceId 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue

if ($diagSettings -and $diagSettings.Count -gt 0) {
    Write-Host "[OK] Diagnostic settings found:" -ForegroundColor Green
    foreach ($d in $diagSettings) {
        Write-Host "     - $($d.name)" -ForegroundColor Gray
    }
} else {
    Write-Host "[WARN] No diagnostic settings found on $aoaiName." -ForegroundColor Yellow
    Write-Host "       Blocked requests won't appear in Sentinel!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "       To fix, run:" -ForegroundColor Yellow
    Write-Host "       az monitor diagnostic-settings create \" -ForegroundColor DarkGray
    Write-Host "         --name 'openai-security-logs' \" -ForegroundColor DarkGray
    Write-Host "         --resource '$resourceId' \" -ForegroundColor DarkGray
    Write-Host "         --workspace '$($workspace.id)' \" -ForegroundColor DarkGray
    Write-Host "         --logs '[{`"category`":`"Audit`",`"enabled`":true},{`"category`":`"RequestResponse`",`"enabled`":true},{`"category`":`"Trace`",`"enabled`":true}]' \" -ForegroundColor DarkGray
    Write-Host "         --metrics '[{`"category`":`"AllMetrics`",`"enabled`":true}]'" -ForegroundColor DarkGray
}
Write-Host ""

# -----------------------------------------------------------
# Step 5: Test API connectivity
# -----------------------------------------------------------
Write-Host "--- Step 5: API Connectivity Test ---" -ForegroundColor Yellow
Write-Host ""

Write-Host "[*] Acquiring Entra ID token..." -ForegroundColor Gray
$token = az account get-access-token --resource https://cognitiveservices.azure.com --query accessToken -o tsv

if (-not $token) {
    Write-Host "[FAIL] Could not acquire token. Check Cognitive Services User role." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Token acquired." -ForegroundColor Green

$uri = "$LabEndpoint/openai/deployments/$LabDeploymentName/chat/completions?api-version=$LabApiVersion"
$testBody = @{
    messages = @(@{ role = "user"; content = "Say hello in one word." })
    max_tokens = 10
} | ConvertTo-Json -Depth 3

$testHeaders = @{
    "Content-Type"  = "application/json"
    "Authorization" = "Bearer $token"
}

Write-Host "[*] Sending test prompt to $LabDeploymentName..." -ForegroundColor Gray
try {
    $response = Invoke-RestMethod -Uri $uri -Method POST -Headers $testHeaders -Body $testBody
    $reply = $response.choices[0].message.content
    Write-Host "[OK] Model responded: '$reply'" -ForegroundColor Green
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    Write-Host "[FAIL] HTTP $statusCode - $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "       Check: endpoint URL, deployment name, and RBAC permissions." -ForegroundColor Red
    exit 1
}
Write-Host ""

# -----------------------------------------------------------
# Summary
# -----------------------------------------------------------
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  Environment Validation Complete" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Tenant:       $LabTenantId" -ForegroundColor White
Write-Host "  Subscription: $LabSubscriptionId" -ForegroundColor White
Write-Host "  Endpoint:     $LabEndpoint" -ForegroundColor White
Write-Host "  Deployment:   $LabDeploymentName" -ForegroundColor White
Write-Host "  Workspace:    $LabWorkspaceName" -ForegroundColor White
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor White
Write-Host "    1. Run attack simulation:  .\tests\test-aml-t0065.ps1" -ForegroundColor White
Write-Host "    2. Run jailbreak tests:    .\tests\test-jailbreak.ps1" -ForegroundColor White
Write-Host "    3. Wait 10-15 min for logs to appear in Sentinel" -ForegroundColor White
Write-Host "    4. Run hunting query:      hunting\ai-alerts-mitre-correlation.kql" -ForegroundColor White
Write-Host ""
