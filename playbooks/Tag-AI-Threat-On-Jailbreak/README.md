# Playbook: Tag AI Threat on Jailbreak Alert

A Microsoft Sentinel playbook (Logic App) that **automatically adds an "AI Threat" tag** to any incident it is triggered on. Designed to be linked to jailbreak or AI-related analytic rules via an automation rule.

## How It Works

```
Analytic Rule (jailbreak detection)
        │
        ▼
Automation Rule (filters for this analytic rule)
        │
        ▼
Playbook (Logic App)
        │
        ▼
Incident tagged with "AI Threat"
```

1. Your analytic rule fires and creates an incident
2. An automation rule triggers this playbook for that incident
3. The playbook updates the incident with the **"AI Threat"** tag

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **Microsoft Sentinel** | Active workspace |
| **Permissions** | Microsoft Sentinel Contributor + Logic App Contributor on the resource group |
| **Analytic Rule** | An existing analytic rule that detects jailbreak attempts |

---

## Step 1: Deploy the Playbook

### Option A — Azure CLI

```bash
# Set your variables
RESOURCE_GROUP="<your-resource-group>"
LOCATION="<your-location>"          # e.g. westeurope

# Deploy the ARM template
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file playbooks/Tag-AI-Threat-On-Jailbreak/azuredeploy.json \
  --parameters PlaybookName="Tag-AI-Threat-On-Jailbreak"
```

### Option B — Azure Portal

1. Go to **Azure Portal** → **Deploy a custom template**
2. Click **Build your own template in the editor**
3. Paste the contents of `azuredeploy.json`
4. Click **Save** → fill in the resource group and parameters → **Review + Create**

### Option C — One-Click Deploy

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2F<your-org>%2F<your-repo>%2Fmain%2Fplaybooks%2FTag-AI-Threat-On-Jailbreak%2Fazuredeploy.json)

> Replace the URL above with your actual raw GitHub URL after pushing this repo.

---

## Step 2: Grant the Playbook Permissions

The playbook uses a **managed identity**. After deployment, grant it the **Microsoft Sentinel Responder** role so it can update incidents.

### Via Azure CLI

```bash
# Get the managed identity object ID (from deployment output)
IDENTITY_OBJECT_ID=$(az logic workflow show \
  --resource-group "$RESOURCE_GROUP" \
  --name "Tag-AI-Threat-On-Jailbreak" \
  --query identity.principalId -o tsv)

# Get your Sentinel workspace resource ID
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group "$RESOURCE_GROUP" \
  --workspace-name "<your-workspace-name>" \
  --query id -o tsv)

# Assign Microsoft Sentinel Responder role
az role assignment create \
  --assignee-object-id "$IDENTITY_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Microsoft Sentinel Responder" \
  --scope "$WORKSPACE_ID"
```

### Via Azure Portal

1. Go to your **Log Analytics workspace** → **Access control (IAM)**
2. Click **+ Add** → **Add role assignment**
3. Role: **Microsoft Sentinel Responder**
4. Members: select **Managed identity** → pick the Logic App **Tag-AI-Threat-On-Jailbreak**
5. Click **Review + assign**

---

## Step 3: Authorize the API Connection

1. Go to **Azure Portal** → **Resource groups** → your resource group
2. Find the resource **azuresentinel-Tag-AI-Threat-On-Jailbreak** (type: API connection)
3. Click **Edit API connection**
4. Click **Authorize** → sign in → **Save**

> If using managed identity, this step may be auto-configured. Verify the connection status shows "Connected".

---

## Step 4: Link the Playbook to Your Analytic Rule via Automation Rule

This is how you connect the playbook to an **existing** analytic rule so it fires automatically on jailbreak incidents.

### Via Azure Portal

1. Go to **Microsoft Sentinel** → **Automation**
2. Click **+ Create** → **Automation rule**
3. Configure the rule:

| Field | Value |
|-------|-------|
| **Name** | Auto-tag AI Threat on Jailbreak |
| **Trigger** | When incident is created |
| **Conditions** | Analytic rule name → **Contains** → `Jailbreak` (or select your specific rule) |
| **Actions** | Run playbook → **Tag-AI-Threat-On-Jailbreak** |
| **Order** | 1 |
| **Status** | Enabled |

4. Click **Apply**

### Via Azure CLI (REST API)

```bash
# Variables
SUBSCRIPTION_ID="<your-subscription-id>"
RESOURCE_GROUP="<your-resource-group>"
WORKSPACE_NAME="<your-workspace-name>"
AUTOMATION_RULE_ID=$(uuidgen)   # or use a fixed GUID
PLAYBOOK_RESOURCE_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Logic/workflows/Tag-AI-Threat-On-Jailbreak"

# Create the automation rule via REST API
az rest --method put \
  --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.OperationalInsights/workspaces/$WORKSPACE_NAME/providers/Microsoft.SecurityInsights/automationRules/$AUTOMATION_RULE_ID?api-version=2024-03-01" \
  --body "{
    \"properties\": {
      \"displayName\": \"Auto-tag AI Threat on Jailbreak\",
      \"order\": 1,
      \"triggeringLogic\": {
        \"isEnabled\": true,
        \"triggersOn\": \"Incidents\",
        \"triggersWhen\": \"Created\",
        \"conditions\": [
          {
            \"conditionType\": \"Property\",
            \"conditionProperties\": {
              \"propertyName\": \"IncidentRelatedAnalyticRuleIds\",
              \"operator\": \"Contains\",
              \"propertyValues\": [
                \"/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.OperationalInsights/workspaces/$WORKSPACE_NAME/providers/Microsoft.SecurityInsights/alertRules/<your-analytic-rule-id>\"
              ]
            }
          }
        ]
      },
      \"actions\": [
        {
          \"order\": 1,
          \"actionType\": \"RunPlaybook\",
          \"actionConfiguration\": {
            \"logicAppResourceId\": \"$PLAYBOOK_RESOURCE_ID\",
            \"tenantId\": \"<your-tenant-id>\"
          }
        }
      ]
    }
  }"
```

> To find your analytic rule ID, go to **Sentinel** → **Analytics** → click your rule → copy the rule ID from the URL or use:
> ```bash
> az rest --method get \
>   --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.OperationalInsights/workspaces/$WORKSPACE_NAME/providers/Microsoft.SecurityInsights/alertRules?api-version=2024-03-01" \
>   | jq '.value[] | {name: .name, displayName: .properties.displayName}'
> ```

---

## Validation

After deployment, verify everything works:

1. **Check the playbook** — Go to **Logic Apps** → **Tag-AI-Threat-On-Jailbreak** → status should be **Enabled**
2. **Check the automation rule** — Go to **Sentinel** → **Automation** → rule should show **Enabled**
3. **Trigger a test** — Run the jailbreak test script (`tests/test-jailbreak.ps1`) to generate alerts
4. **Verify the tag** — Open the resulting incident in Sentinel → the **"AI Threat"** tag should appear

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Playbook doesn't run | Check the automation rule is enabled and the condition matches your analytic rule |
| "Unauthorized" in Logic App runs | Grant the managed identity **Microsoft Sentinel Responder** on the workspace |
| Tag not appearing | Open the Logic App run history to see the API response — look for 403/404 errors |
| API connection error | Re-authorize the `azuresentinel-*` API connection in the portal |
