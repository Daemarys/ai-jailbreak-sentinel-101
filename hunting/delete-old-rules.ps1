. "$PSScriptRoot\..\lab.config.ps1"

$sentinelBase = "https://management.azure.com/subscriptions/$LabSubscriptionId/resourceGroups/$LabResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$LabWorkspaceName/providers/Microsoft.SecurityInsights"
$apiVersion = "api-version=2024-03-01"

Write-Output "Listing existing AI Jailbreak rules..."
$json = az rest --method GET --uri "$sentinelBase/alertRules?${apiVersion}" -o json
$rules = ($json | ConvertFrom-Json).value | Where-Object { $_.properties.displayName -like "AI Jailbreak*" }
Write-Output ("Found " + $rules.Count + " rules to delete")
foreach ($r in $rules) {
    $ruleId = $r.name
    Write-Output "Deleting: $($r.properties.displayName) ($ruleId)"
    az rest --method DELETE --uri "$sentinelBase/alertRules/${ruleId}?${apiVersion}" | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Output "  OK" } else { Write-Output "  FAILED" }
}
Write-Output "Done."
