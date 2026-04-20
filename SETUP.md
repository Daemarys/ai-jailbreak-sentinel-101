# Setup & Deployment Guide

Complete instructions for deploying the AI Jailbreak Lab end-to-end: diagnostic logging, custom prompt-log ingestion, Sentinel analytic rules, and the auto-tag playbook.

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

> **Heads-up:** `AzureDiagnostics` carries only request **metadata** for Azure OpenAI (counts, lengths, timing) — not the prompt or response text. To let Sentinel pattern-match on content, the test scripts ship the full prompt and response to a custom table (`AIPromptLog_CL`) via the Log Analytics HTTP Data Collector API. That table is created automatically on the first test run (see Step 3).

---

## Step 3: Configure the Lab

Populate `lab.config.ps1` with your tenant, Azure OpenAI, and Sentinel values. See [NEW-TENANT-SETUP.md § Step 7](NEW-TENANT-SETUP.md#step-7-configure-the-lab-for-the-new-tenant) for the full walk-through.

You'll specifically need the Log Analytics workspace **customer ID** and **primary shared key** — the test scripts use the HTTP Data Collector API with HMAC-signed requests to ingest prompt/response records into `AIPromptLog_CL`.

```powershell
# Customer ID (safe)
az monitor log-analytics workspace show -g <rg> -n <ws> --query customerId -o tsv

# Primary shared key (SECRET — store in .ws-key.txt, which is gitignored)
az monitor log-analytics workspace get-shared-keys -g <rg> -n <ws> `
  --query primarySharedKey -o tsv | Out-File .ws-key.txt -NoNewline -Encoding ASCII
```

Validate end-to-end connectivity:

```powershell
.\setup\deploy-lab.ps1
```

---

## Step 4: Run a Test to Create the Custom Table

The first successful POST to the Data Collector API creates `AIPromptLog_CL` automatically. Kick it off with the smoke test:

```powershell
.\tests\test-jailbreak.ps1
```

Wait 5–10 minutes, then verify:

```kql
AIPromptLog_CL
| take 10
| project TimeGenerated, TestName_s, Status_s, Prompt_s, Response_s
```

---

## Step 5: Deploy Sentinel Analytic Rules

Deploy the 4 custom rules that detect inference-gap bypasses on the new `AIPromptLog_CL` table:

```powershell
.\hunting\deploy-analytics-rules.ps1
```

This creates (or updates, on re-run) four scheduled rules:

| Rule | Severity | Detection |
|------|----------|-----------|
| AI Jailbreak - Educational Framing Attack | High | Academic/certification framing + attack keywords in the prompt |
| AI Jailbreak - Creative Writing Attack | High | Fiction/roleplay framing + harmful verbs in the prompt |
| AI Jailbreak - Rapid Probing (Consistency Attack) | Medium | ≥5 requests with ≤2 distinct prompts from the same caller within a 1-minute bin |
| AI Jailbreak - Attack Tools in Response | High | Known offensive tool names (metasploit, mimikatz, sqlmap, …) in the model's response |

Rules run every 5 minutes with a 30-minute lookback to tolerate Data Collector API ingestion latency. The rule IDs are deterministically derived from the display name, so re-running `deploy-analytics-rules.ps1` updates existing rules in place instead of creating duplicates.

---

## Step 6: Run the Full Attack Simulation

```powershell
# Full MITRE ATLAS AML.T0065 simulation + Sentinel rule triggers (30 tests, ~5 min)
.\tests\test-aml-t0065.ps1

# Quick smoke test (10 tests)
.\tests\test-jailbreak.ps1
```

Within ~10 minutes you should see rows in both tables and SecurityAlerts firing:

```kql
// Did the calls ingest?
AIPromptLog_CL
| where TimeGenerated > ago(1h)
| summarize count() by Status_s

// Did the gateway see them?
AzureDiagnostics
| where TimeGenerated > ago(1h)
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| summarize count() by ResultSignature

// Did the analytic rules fire?
SecurityAlert
| where TimeGenerated > ago(2h)
| where AlertName startswith "AI Jailbreak"
| project TimeGenerated, AlertName, AlertSeverity
| order by TimeGenerated desc
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
- [ ] `AzureDiagnostics` table receiving rows from `MICROSOFT.COGNITIVESERVICES`
- [ ] `lab.config.ps1` populated (including `$LabWorkspaceCustomerId` and `$LabWorkspaceSharedKey`)
- [ ] `.\setup\deploy-lab.ps1` reports all checks passing
- [ ] `AIPromptLog_CL` table exists and contains rows after running a test
- [ ] 4 analytic rules deployed via `.\hunting\deploy-analytics-rules.ps1`
- [ ] `SecurityAlert` contains rows with `AlertName` starting with "AI Jailbreak" after running `test-aml-t0065.ps1`
- [ ] (Optional) Tag-AI-Threat playbook deployed and linked to analytic rules

---

## Required Permissions

| Action | Role |
|--------|------|
| Deploy agent | Security Copilot Contributor |
| Query Sentinel | Security Reader |
| Create analytics rules | Microsoft Sentinel Contributor |
| Run attack scripts | Cognitive Services User |
| Enable diagnostics | Monitoring Contributor |
