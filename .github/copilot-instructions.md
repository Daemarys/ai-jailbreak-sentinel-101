# Copilot Instructions for AI Jailbreak Lab

## Project Context

This is an AI security workshop lab. Attendees test Azure OpenAI content safety filters by running jailbreak attack simulations, then investigate the results in Microsoft Sentinel.

## Key Workflow: Lab Configuration

When a user asks to "configure the lab", "set up my environment", or "fill in lab.config.ps1":

1. **Check Azure login** — Run `az account show` to verify the user is signed in. If not, guide them through `az login --tenant <tenant-id>`.
2. **Discover Azure OpenAI resources** — Run `az cognitiveservices account list` to find the endpoint and resource group.
3. **Discover model deployments** — For each OpenAI resource, run `az cognitiveservices account deployment list` to find deployed models (prefer gpt-4o).
4. **Discover Sentinel workspace** — Run `az monitor log-analytics workspace list` to find the Log Analytics workspace.
5. **Get tenant and subscription IDs** — Extract from `az account show`.
6. **Get the workspace customer ID and primary shared key** — The test scripts ship prompt/response telemetry to `AIPromptLog_CL` via the Data Collector API, which requires these.
   - `az monitor log-analytics workspace show -g <rg> -n <ws> --query customerId -o tsv`
   - `az monitor log-analytics workspace get-shared-keys -g <rg> -n <ws> --query primarySharedKey -o tsv`
   - Store the key in `.ws-key.txt` (gitignored) rather than inlining it in the config file.
7. **Write lab.config.ps1** — Copy from `lab.config.example.ps1` if it doesn't exist, then populate all `<placeholder>` values with discovered resources.
8. **Validate** — Run `.\setup\deploy-lab.ps1` to confirm connectivity.

If the user has multiple Azure OpenAI resources, prefer the one with model deployments. If there are multiple Sentinel workspaces, ask the user which one to use.

## Config File: lab.config.ps1

- `$LabTenantId` — Entra ID tenant ID
- `$LabEndpoint` — Azure OpenAI endpoint URL (e.g. `https://myresource.cognitiveservices.azure.com`)
- `$LabDeploymentName` — Model deployment name (e.g. `gpt-4o`)
- `$LabApiVersion` — API version, default `2024-10-21`
- `$LabAoaiResourceGroup` — Resource group of the Azure OpenAI resource
- `$LabSubscriptionId` — Azure subscription ID
- `$LabResourceGroup` — Resource group of the Sentinel/Log Analytics workspace (may differ from OpenAI RG)
- `$LabWorkspaceName` — Log Analytics workspace name
- `$LabWorkspaceCustomerId` — Log Analytics workspace customer GUID (for Data Collector API ingestion)
- `$LabWorkspaceSharedKey` — Primary shared key (use `(Get-Content .ws-key.txt -Raw).Trim()` to avoid storing inline)
- `$LabPromptLogTable` — Custom table name, default `AIPromptLog` (creates `AIPromptLog_CL`)

## Test Scripts

- `tests/test-jailbreak.ps1` — Quick 10-test smoke test (~2 min)
- `tests/test-aml-t0065.ps1` — Full MITRE ATLAS AML.T0065 simulation + Sentinel rule triggers, 24 tests (~5 min). Ships prompt/response records to `AIPromptLog_CL`.
- Both scripts source `lab.config.ps1` automatically

## Command Explanation

When executing terminal commands, always provide a one-line explanation of what the command does before running it.
