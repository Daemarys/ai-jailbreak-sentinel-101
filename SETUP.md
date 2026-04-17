# Setup & Deployment Guide

Complete instructions for deploying the Sentinel AI Threat Report Agent.

---

## Step 1: Enable Diagnostic Logging on Azure OpenAI

Your Azure OpenAI resource must send logs to a Log Analytics workspace.

### Via Azure CLI

```bash
# Get your OpenAI resource ID
RESOURCE_ID=$(az cognitiveservices account show \
  --name <your-openai-resource-name> \
  --resource-group <your-resource-group> \
  --query id -o tsv)

# Get your Log Analytics workspace ID
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group <your-resource-group> \
  --workspace-name <your-workspace-name> \
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

### Via Azure Portal

1. Navigate to your **Azure OpenAI** resource
2. Go to **Monitoring** → **Diagnostic settings**
3. Click **+ Add diagnostic setting**
4. Check: **Audit**, **RequestResponse**, **Trace**, **AllMetrics**
5. Select **Send to Log Analytics workspace** → choose your Sentinel workspace
6. Click **Save**

> Logs take 5–15 minutes to start appearing.

---

## Step 2: Verify Data in Sentinel

Open your Log Analytics workspace and run:

```kql
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| take 10
```

If no results, wait 15 minutes and retry.

---

## Step 3: Configure the Agent Manifest

### Find your values

```bash
az account show --query tenantId -o tsv          # Tenant ID
az account show --query id -o tsv                # Subscription ID
az monitor log-analytics workspace list \
  --query "[].{Name:name, RG:resourceGroup}" -o table
```

### Update the YAML

In `sentinel-ai-threat-report-agent.yaml`, find and replace these 4 placeholders in **all 6 KQL skills**:

| Placeholder | Replace With |
|-------------|-------------|
| `<your-tenant-id>` | Your Entra ID tenant ID |
| `<your-subscription-id>` | Subscription containing Sentinel |
| `<your-resource-group>` | Resource group of the workspace |
| `<your-workspace-name>` | Log Analytics workspace name |

---

## Step 4: Deploy to Security Copilot

1. Open [Security Copilot](https://securitycopilot.microsoft.com)
2. Go to **Agents** → **Build**
3. Upload `sentinel-ai-threat-report-agent.yaml`
4. Wait for validation
5. The agent appears under **Agents** as "Sentinel AI Threat Report Agent"

### Use the agent

- **Interactive**: Click **Chat with agent** → use a starter prompt or ask a question
- **Scheduled**: Click **Run** → select **ScheduledBlockedRequestCheck** → agent polls every 5 min

---

## Step 5: Create Sentinel Analytics Rules (Optional)

These rules generate the alerts and incidents the agent reports on.

### Rule 1: AI Jailbreak Attempt Detected (Medium)

```kql
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| where ResultSignature == "400"
| summarize AttemptCount = count(), 
    FirstAttempt = min(TimeGenerated),
    LastAttempt = max(TimeGenerated) 
  by CallerIPAddress, _ResourceId
| where AttemptCount > 3
```

Create via CLI:

```bash
az sentinel alert-rule create \
  --resource-group <your-rg> \
  --workspace-name <your-workspace> \
  --rule-id "jailbreak-detect-01" \
  --scheduled-alert-rule \
    query="<KQL above>" \
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
```

### Rule 2: AI Brute-Force Jailbreak Detected (High)

```kql
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| where ResultSignature == "400"
| summarize AttemptCount = count()
  by CallerIPAddress, bin(TimeGenerated, 1h)
| where AttemptCount > 10
```

### Rule 3: AI High Block Ratio Detected (Medium)

```kql
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| summarize Total = count(), 
    Blocked = countif(ResultSignature == "400")
  by CallerIPAddress
| extend BlockRatio = round(todouble(Blocked) / Total * 100, 1)
| where BlockRatio > 50 and Total > 5
```

---

## Step 6: Run Attack Simulation (Optional)

Test that blocked requests flow through to the agent.

```powershell
# Full MITRE ATLAS AML.T0065 simulation (21 tests)
.\tests\test-aml-t0065.ps1

# Quick smoke test (10 tests)
.\tests\test-jailbreak.ps1
```

After running, wait 5–15 minutes and verify in Sentinel:

```kql
AzureDiagnostics
| where TimeGenerated > ago(1h)
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| where ResultSignature == "400"
| summarize count() by CallerIPAddress
```

---

## Step 7: Deploy the Auto-Tag Playbook (Optional)

Automatically tag jailbreak incidents with **"AI Threat"** using a Logic App playbook.

See full instructions: [`playbooks/Tag-AI-Threat-On-Jailbreak/README.md`](playbooks/Tag-AI-Threat-On-Jailbreak/README.md)

**Quick deploy:**

```bash
az deployment group create \
  --resource-group <your-resource-group> \
  --template-file playbooks/Tag-AI-Threat-On-Jailbreak/azuredeploy.json \
  --parameters PlaybookName="Tag-AI-Threat-On-Jailbreak"
```

After deploying, create an **automation rule** in Sentinel to link the playbook to your jailbreak analytic rule. The playbook README has step-by-step instructions for both Portal and CLI.

---

## Verification Checklist

- [ ] Diagnostic logging enabled on Azure OpenAI
- [ ] Logs appearing in `AzureDiagnostics` table
- [ ] YAML updated with your Tenant/Subscription/RG/Workspace
- [ ] Agent uploaded and visible in Security Copilot
- [ ] "Chat with agent" returns data when prompted
- [ ] (Optional) Sentinel analytics rules created
- [ ] (Optional) Attack simulation run and alerts generated
- [ ] (Optional) Tag-AI-Threat playbook deployed and linked to analytic rule

---

## Required Permissions

| Action | Role |
|--------|------|
| Deploy agent | Security Copilot Contributor |
| Query Sentinel | Security Reader |
| Create analytics rules | Microsoft Sentinel Contributor |
| Run attack scripts | Cognitive Services User |
| Enable diagnostics | Monitoring Contributor |
