# New Tenant Deployment Guide

Step-by-step guide to deploy the AI Jailbreak Lab in a **new Azure tenant** from scratch.

---

## Prerequisites

| Requirement | Details |
|---|---|
| Azure subscription | Pay-as-you-go or Enterprise with AI services enabled |
| Entra ID role | Global Administrator or Subscription Owner (for initial setup) |
| Azure CLI | v2.60+ installed locally ([install](https://learn.microsoft.com/cli/azure/install-azure-cli)) |
| PowerShell 7+ | For running test scripts |

---

## Step 0: Authenticate to the New Tenant

```bash
# Log out of any existing tenant
az logout

# Log in to the new tenant (interactive browser flow)
az login --tenant <new-tenant-id>

# Verify you're in the correct tenant
az account show --query "{TenantId:tenantId, Subscription:name, SubscriptionId:id}" -o table

# If you have multiple subscriptions, select the right one
az account set --subscription <subscription-id>
```

Save these values — you'll need them throughout:

```bash
# Export for convenience
$TENANT_ID = az account show --query tenantId -o tsv
$SUBSCRIPTION_ID = az account show --query id -o tsv
echo "Tenant:       $TENANT_ID"
echo "Subscription: $SUBSCRIPTION_ID"
```

---

## Step 1: Create Resource Group

```bash
az group create \
  --name rg-ai-jailbreak-lab \
  --location eastus2
```

> **Tip:** Use `eastus2` or `swedencentral` — these regions have the best Azure OpenAI + AI Foundry model availability.

---

## Step 2: Create Log Analytics Workspace + Enable Sentinel

```bash
# Create Log Analytics workspace
az monitor log-analytics workspace create \
  --resource-group rg-ai-jailbreak-lab \
  --workspace-name law-ai-jailbreak-lab \
  --location eastus2 \
  --retention-time 30

# Enable Microsoft Sentinel on the workspace
az sentinel onboarding-state create \
  --resource-group rg-ai-jailbreak-lab \
  --workspace-name law-ai-jailbreak-lab \
  --name default
```

Save the workspace name:

```bash
$WORKSPACE_NAME = "law-ai-jailbreak-lab"
$RESOURCE_GROUP = "rg-ai-jailbreak-lab"
```

---

## Step 3: Create Azure OpenAI Resource

```bash
az cognitiveservices account create \
  --name aoai-jailbreak-lab \
  --resource-group rg-ai-jailbreak-lab \
  --location eastus2 \
  --kind OpenAI \
  --sku S0 \
  --custom-domain aoai-jailbreak-lab
```

> The `--custom-domain` creates the endpoint: `https://aoai-jailbreak-lab.openai.azure.com`

---

## Step 4: Deploy Models

### 4a: Deploy GPT-4o (Primary Test Target)

```bash
az cognitiveservices account deployment create \
  --name aoai-jailbreak-lab \
  --resource-group rg-ai-jailbreak-lab \
  --deployment-name gpt-4o \
  --model-name gpt-4o \
  --model-version "2024-11-20" \
  --model-format OpenAI \
  --sku-capacity 10 \
  --sku-name GlobalStandard
```

### 4b: Deploy DeepSeek via Azure AI Foundry (Optional)

DeepSeek is available as a **serverless API** (Model-as-a-Service) deployment:

1. Open [Azure AI Foundry](https://ai.azure.com)
2. Create or select an **AI Hub** in the same resource group
3. Go to **Model catalog** → search for **DeepSeek-R1** or **DeepSeek-V3**
4. Click **Deploy** → **Serverless API**
5. Accept the marketplace terms
6. Note the endpoint URL and key (you'll need these for test scripts)

> **Important:** Serverless API deployments log to a different diagnostics path. Ensure diagnostic settings cover the AI Hub resource too. See [Step 5b](#5b-enable-diagnostics-on-ai-hub-for-deepseek).

### 4c: Verify Deployments

```bash
# List Azure OpenAI deployments
az cognitiveservices account deployment list \
  --name aoai-jailbreak-lab \
  --resource-group rg-ai-jailbreak-lab \
  -o table
```

---

## Step 5: Enable Diagnostic Logging

### 5a: Enable Diagnostics on Azure OpenAI

```bash
# Get resource IDs
RESOURCE_ID=$(az cognitiveservices account show \
  --name aoai-jailbreak-lab \
  --resource-group rg-ai-jailbreak-lab \
  --query id -o tsv)

WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group rg-ai-jailbreak-lab \
  --workspace-name law-ai-jailbreak-lab \
  --query id -o tsv)

# Create diagnostic settings
az monitor diagnostic-settings create \
  --name "openai-security-logs" \
  --resource "$RESOURCE_ID" \
  --workspace "$WORKSPACE_ID" \
  --logs '[
    {"category": "Audit", "enabled": true},
    {"category": "RequestResponse", "enabled": true},
    {"category": "Trace", "enabled": true}
  ]' \
  --metrics '[{"category": "AllMetrics", "enabled": true}]'
```

### 5b: Enable Diagnostics on AI Hub (for DeepSeek)

If you deployed DeepSeek via AI Foundry, also enable diagnostics on the AI Hub:

```bash
HUB_RESOURCE_ID=$(az resource list \
  --resource-group rg-ai-jailbreak-lab \
  --resource-type "Microsoft.MachineLearningServices/workspaces" \
  --query "[0].id" -o tsv)

az monitor diagnostic-settings create \
  --name "aihub-security-logs" \
  --resource "$HUB_RESOURCE_ID" \
  --workspace "$WORKSPACE_ID" \
  --logs '[
    {"category": "AmlComputeClusterEvent", "enabled": true},
    {"category": "AmlRunStatusChangedEvent", "enabled": true}
  ]' \
  --metrics '[{"category": "AllMetrics", "enabled": true}]'
```

> **Note:** For MaaS models, the request-level logging structure differs from Azure OpenAI. You may see logs under the `MachineLearningServices` resource provider instead of `COGNITIVESERVICES`. Adjust hunting queries accordingly.

### 5c: Connect Defender for Cloud to Sentinel

Diagnostic settings send **raw API request logs** to Sentinel. But Defender for AI **security alerts** (jailbreak detected, brute-force detected) travel a different path — they go to Microsoft Defender XDR first. To get them into Sentinel, you need the **Microsoft Defender for Cloud** data connector:

**Option A — Azure Portal (recommended)**

1. Open **Microsoft Sentinel** → your workspace → **Content hub**
2. Search for **Microsoft Defender for Cloud** → Install/Update the solution
3. Go to **Data connectors** → find **Subscription-based Microsoft Defender for Cloud (Legacy)** or **Tenant-based Microsoft Defender for Cloud**
4. Select your subscription → click **Connect**
5. Enable **Bi-directional sync** so incident status syncs between XDR and Sentinel

> **Portal shortcut:** [https://portal.azure.com/#view/Microsoft_Azure_Security_Insights/DataConnectorsListBlade](https://portal.azure.com/#view/Microsoft_Azure_Security_Insights/DataConnectorsListBlade)

**Option B — Azure CLI**

```bash
# Install the Sentinel Defender for Cloud connector
az sentinel data-connector create \
  --resource-group rg-ai-jailbreak-lab \
  --workspace-name law-ai-jailbreak-lab \
  --data-connector-id "defender-for-cloud-connector" \
  --microsoft-cloud-app-security "{\"dataTypes\":{\"alerts\":{\"state\":\"Enabled\"}}}"
```

> **Cost note:** The Defender for Cloud data connector itself is **free** — `SecurityAlert` and `SecurityIncident` tables are [free data sources](https://learn.microsoft.com/en-us/azure/sentinel/billing?tabs=simplified%2Ccommitment-tiers#free-data-sources) in Sentinel and do not count toward your Log Analytics ingestion costs.

**Without this connector:**
- Alerts appear in **Defender XDR** but **not** in Sentinel
- The `SecurityAlert` table in Log Analytics stays empty
- Sentinel incidents are not created
- The hunting query (`ai-alerts-mitre-correlation.kql`) returns no results

### 5d: Verify Logs Are Flowing

Wait 10-15 minutes after enabling diagnostics, then run:

```kql
-- Check raw request logs
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| take 10

-- Check security alerts (requires Defender connector)
SecurityAlert
| where ProviderName has "AI"
| take 10
```

### 5e: Cost Summary

| Data Source | Table | Cost |
|---|---|---|
| **Diagnostic settings** (raw API logs) | `AzureDiagnostics` | Billed per GB ingested into Log Analytics. ~0.5 KB per request → 30 tests ≈ negligible. At scale, budget ~$2.76/GB ([pricing](https://azure.microsoft.com/en-us/pricing/details/monitor/)) |
| **Defender for AI alerts** | `SecurityAlert`, `SecurityIncident` | **Free** — [free data sources](https://learn.microsoft.com/en-us/azure/sentinel/billing?tabs=simplified%2Ccommitment-tiers#free-data-sources) in Sentinel |
| **Defender for Cloud plan** (AI workload protection) | N/A | Included with Defender for Cloud (CSPM or CWP plan). Check your plan tier |

---

## Step 6: Grant Permissions to Lab Users

### Required Roles

```bash
USER_ID=$(az ad user show --id user@yourdomain.com --query id -o tsv)

# Run test scripts (call Azure OpenAI)
az role assignment create \
  --assignee $USER_ID \
  --role "Cognitive Services User" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-ai-jailbreak-lab"

# View Sentinel data
az role assignment create \
  --assignee $USER_ID \
  --role "Microsoft Sentinel Reader" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-ai-jailbreak-lab"

# Create analytics rules and manage incidents
az role assignment create \
  --assignee $USER_ID \
  --role "Microsoft Sentinel Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-ai-jailbreak-lab"
```

### Full Role Matrix

| Role | Purpose | Scope |
|---|---|---|
| Cognitive Services User | Call Azure OpenAI API (run tests) | Resource group |
| Microsoft Sentinel Reader | Query logs and view incidents | Resource group |
| Microsoft Sentinel Contributor | Create analytics rules, manage incidents | Resource group |
| Monitoring Contributor | Enable/modify diagnostic settings | Resource group |

---

## Step 7: Configure the Lab for the New Tenant

### 7a: Populate `lab.config.ps1`

All test scripts and analytic-rule deployment read from `lab.config.ps1` at the repo root. Copy the template and fill it in:

```powershell
Copy-Item lab.config.example.ps1 lab.config.ps1
```

Then edit `lab.config.ps1` and set:

| Variable | How to get it |
|---|---|
| `$LabTenantId` | `az account show --query tenantId -o tsv` |
| `$LabSubscriptionId` | `az account show --query id -o tsv` |
| `$LabEndpoint` | `https://<aoai-name>.cognitiveservices.azure.com` |
| `$LabDeploymentName` | Your deployment name (e.g. `gpt-4o`) |
| `$LabApiVersion` | `2024-10-21` (default is fine) |
| `$LabAoaiResourceGroup` | RG of the Azure OpenAI resource |
| `$LabResourceGroup` | RG of the Sentinel / Log Analytics workspace |
| `$LabWorkspaceName` | Log Analytics workspace name |
| `$LabWorkspaceCustomerId` | Workspace GUID (see below) |
| `$LabWorkspaceSharedKey` | Primary shared key (see below) |
| `$LabPromptLogTable` | `AIPromptLog` (creates `AIPromptLog_CL`) |

### 7b: Get the Log Analytics workspace ID and shared key

The test scripts ship prompt/response telemetry to a custom table (`AIPromptLog_CL`) via the Log Analytics HTTP Data Collector API. This requires the workspace **customer ID** (GUID) and **primary shared key**:

```powershell
$rg = "<your-sentinel-rg>"
$ws = "<your-workspace-name>"

# Workspace customer ID (safe to commit)
az monitor log-analytics workspace show `
  --resource-group $rg --workspace-name $ws `
  --query customerId -o tsv

# Primary shared key (SECRET — do NOT commit)
az monitor log-analytics workspace get-shared-keys `
  --resource-group $rg --workspace-name $ws `
  --query primarySharedKey -o tsv
```

Paste the customer ID into `$LabWorkspaceCustomerId`. For the shared key, either paste it directly into `$LabWorkspaceSharedKey` in `lab.config.ps1` (the whole file is gitignored), or store it in `.ws-key.txt` (also gitignored) and reference it:

```powershell
$LabWorkspaceSharedKey = (Get-Content "$PSScriptRoot\.ws-key.txt" -Raw).Trim()
```

> **Why a shared key?** The Data Collector API uses HMAC-SHA256 request signing, not Entra tokens. The key grants write access only to this one workspace. Rotate it via `az monitor log-analytics workspace get-shared-keys --regenerate` if exposed.

### 7c: Re-authenticate to the New Tenant

The test scripts use Entra ID tokens. Before running, ensure you're logged in to the new tenant:

```powershell
# Log in to the new tenant
az login --tenant <new-tenant-id>

# Verify
az account show --query "{Tenant:tenantId, Sub:name}" -o table

# Test token acquisition
az account get-access-token --resource https://cognitiveservices.azure.com --query accessToken -o tsv
```

### 7c: Run a Quick Validation

```powershell
.\tests\test-jailbreak.ps1
```

Expected: Most tests return `[BLOCKED]` (HTTP 400) — confirming content filters are active and logs are generated.

---

## Step 8: Create Sentinel Analytics Rules

```bash
# Rule 1: AI Jailbreak Attempt Detected (Medium severity)
# Fires when >3 blocked requests from the same IP in 24h
az sentinel alert-rule create \
  --resource-group rg-ai-jailbreak-lab \
  --workspace-name law-ai-jailbreak-lab \
  --rule-id "jailbreak-detect-01" \
  --scheduled-alert-rule \
    query="AzureDiagnostics | where ResourceProvider == 'MICROSOFT.COGNITIVESERVICES' | where ResultSignature == '400' | summarize AttemptCount=count(), FirstAttempt=min(TimeGenerated), LastAttempt=max(TimeGenerated) by CallerIPAddress, _ResourceId | where AttemptCount > 3" \
    query-frequency="PT5M" \
    query-period="P1D" \
    severity="Medium" \
    trigger-operator="GreaterThan" \
    trigger-threshold=0 \
    display-name="AI Jailbreak Attempt Detected" \
    description="More than 3 blocked AI requests from same IP in 24h" \
    enabled=true \
    tactics="InitialAccess" \
    kind="Scheduled"

# Rule 2: AI Brute-Force Jailbreak (High severity)
# Fires when >10 blocked requests in 1 hour
az sentinel alert-rule create \
  --resource-group rg-ai-jailbreak-lab \
  --workspace-name law-ai-jailbreak-lab \
  --rule-id "brute-force-jailbreak-01" \
  --scheduled-alert-rule \
    query="AzureDiagnostics | where ResourceProvider == 'MICROSOFT.COGNITIVESERVICES' | where ResultSignature == '400' | summarize AttemptCount=count() by CallerIPAddress, bin(TimeGenerated, 1h) | where AttemptCount > 10" \
    query-frequency="PT5M" \
    query-period="PT1H" \
    severity="High" \
    trigger-operator="GreaterThan" \
    trigger-threshold=0 \
    display-name="AI Brute-Force Jailbreak Detected" \
    description="More than 10 blocked AI requests from same IP in 1 hour" \
    enabled=true \
    tactics="InitialAccess" \
    kind="Scheduled"

# Rule 3: AI High Block Ratio (Medium severity)
# Fires when >50% of requests from an IP are blocked
az sentinel alert-rule create \
  --resource-group rg-ai-jailbreak-lab \
  --workspace-name law-ai-jailbreak-lab \
  --rule-id "high-block-ratio-03" \
  --scheduled-alert-rule \
    query="AzureDiagnostics | where ResourceProvider == 'MICROSOFT.COGNITIVESERVICES' | summarize Total=count(), Blocked=countif(ResultSignature == '400') by CallerIPAddress | extend BlockRatio=round(todouble(Blocked)/Total*100, 1) | where BlockRatio > 50 and Total > 5" \
    query-frequency="PT5M" \
    query-period="P1D" \
    severity="Medium" \
    trigger-operator="GreaterThan" \
    trigger-threshold=0 \
    display-name="AI High Block Ratio Detected" \
    description="More than 50 percent of AI requests from an IP are blocked" \
    enabled=true \
    tactics="InitialAccess" \
    kind="Scheduled"
```

---

## Step 9: Deploy Auto-Tag Playbook

```bash
az deployment group create \
  --resource-group rg-ai-jailbreak-lab \
  --template-file playbooks/Tag-AI-Threat-On-Jailbreak/azuredeploy.json \
  --parameters PlaybookName="Tag-AI-Threat-On-Jailbreak"
```

Then link it via an automation rule — see [`playbooks/Tag-AI-Threat-On-Jailbreak/README.md`](playbooks/Tag-AI-Threat-On-Jailbreak/README.md) for details.

> **Remember:** Update the subscription ID and workspace name in `playbooks/Tag-AI-Threat-On-Jailbreak/automation-rule-body.json` to match the new tenant.

---

## Multi-Model Testing Strategy

### Models Available in Azure AI Foundry

These deploy natively and integrate with the full Sentinel detection pipeline:

| Model | Deploy Method | Content Safety | Sentinel Logs |
|---|---|---|---|
| GPT-4o / GPT-4.1 | Azure OpenAI deployment | Azure AI Content Safety | `AzureDiagnostics` (COGNITIVESERVICES) |
| DeepSeek-R1 / V3 | Serverless API (MaaS) | Azure AI Content Safety | `AzureDiagnostics` (MaaS) |
| Phi-4 / Phi-3.5 | Serverless API (MaaS) | Azure AI Content Safety | `AzureDiagnostics` (MaaS) |
| Llama 3.x / 4 | Serverless API (MaaS) | Azure AI Content Safety | `AzureDiagnostics` (MaaS) |
| Mistral / Mixtral | Serverless API (MaaS) | Azure AI Content Safety | `AzureDiagnostics` (MaaS) |

### Models NOT in Foundry (Grok, Claude, etc.)

For models like **Grok** (xAI) that are not available in Azure:

**Option A — Skip and adapt the technique.** The jailbreak *techniques* (Developer Mode, banned-string suppression) are model-agnostic. Adapt the Grok prompts to target GPT-4o or DeepSeek in Foundry. This is the simplest approach and still tests the detection pipeline.

**Option B — Azure API Management proxy.** Deploy APIM as a gateway to external APIs:

```
Test Script → APIM (in Azure, logged) → xAI Grok API
                 ↓
         Log Analytics / Sentinel
```

This requires a custom analytics rule since logs come from `MICROSOFT.APIMANAGEMENT` instead of `COGNITIVESERVICES`.

**Option C — VM browsing (not recommended).** A VM user on grok.com produces no prompt-level telemetry in Sentinel — only network/endpoint logs from Defender. Not useful for this lab's detection model.

### Recommended Approach for the Lab

1. Deploy **GPT-4o** + **DeepSeek-R1** in Foundry (covers OpenAI and open-source models)
2. Adapt all tuxsharxsec jailbreak **techniques** for these two models
3. Run test scripts → Content Safety blocks → Sentinel alerts fire
4. (Optional) Add APIM proxy for Grok if xAI-specific testing is required

---

## Quick Reference: Values to Collect

After setup, record these values for team use:

```
Tenant ID:          ________________________________
Subscription ID:    ________________________________
Resource Group:     rg-ai-jailbreak-lab
Azure OpenAI Name:  aoai-jailbreak-lab
Endpoint:           https://aoai-jailbreak-lab.openai.azure.com
Deployment Name:    gpt-4o
Workspace Name:     law-ai-jailbreak-lab
Region:             eastus2
```

---

## Verification Checklist

- [ ] Logged in to the correct tenant (`az account show`)
- [ ] Resource group created
- [ ] Log Analytics workspace + Sentinel enabled
- [ ] Azure OpenAI resource created
- [ ] GPT-4o model deployed
- [ ] (Optional) DeepSeek deployed via AI Foundry
- [ ] Diagnostic logging enabled on Azure OpenAI
- [ ] Diagnostic logging enabled on AI Hub (if DeepSeek deployed)
- [ ] Logs appearing in `AzureDiagnostics` table
- [ ] Lab user permissions granted
- [ ] Test scripts updated with new endpoint/deployment
- [ ] Test scripts run successfully (tokens acquired, requests sent)
- [ ] Blocked requests visible in Sentinel
- [ ] Analytics rules created
- [ ] Auto-tag playbook deployed and linked
