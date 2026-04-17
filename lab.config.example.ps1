# ============================================================
# AI Jailbreak Lab - Environment Configuration
# ============================================================
# Copy this file to lab.config.ps1 and fill in your values.
# All test scripts source this file automatically.
#
# TIP: Ask GitHub Copilot to configure this for you!
#   In the Copilot Chat panel, type:
#   "Configure the lab for my tenant — discover my Azure OpenAI
#    and Sentinel resources and fill in lab.config.ps1"
#   Copilot will run Azure CLI commands to find your resources
#   and populate the values below automatically.
# ============================================================

# --- Azure Tenant ---
# Discovery: az account show --query tenantId -o tsv
$LabTenantId             = "<your-tenant-id>"

# --- Azure OpenAI ---
# Discovery: az cognitiveservices account list --query "[].{Name:name, Endpoint:properties.endpoint, RG:resourceGroup}" -o table
# Then for deployments: az cognitiveservices account deployment list --name <name> --resource-group <rg> --query "[].{Name:name, Model:properties.model.name}" -o table
$LabEndpoint             = "<your-aoai-endpoint>"        # e.g. https://aoai-jailbreak-lab.openai.azure.com
$LabDeploymentName       = "<your-deployment-name>"       # e.g. gpt-4o
$LabApiVersion           = "2024-10-21"
$LabAoaiResourceGroup    = "<your-aoai-resource-group>"   # RG containing the Azure OpenAI resource

# --- Sentinel / Log Analytics ---
# Discovery: az monitor log-analytics workspace list --query "[].{Name:name, RG:resourceGroup}" -o table
$LabSubscriptionId       = "<your-subscription-id>"       # az account show --query id -o tsv
$LabResourceGroup        = "<your-resource-group>"        # RG containing the Sentinel workspace (may differ from OpenAI RG)
$LabWorkspaceName        = "<your-workspace-name>"

# --- Optional: DeepSeek via AI Foundry (MaaS) ---
$LabDeepSeekEndpoint = ""    # e.g. https://<hub-name>.eastus2.models.ai.azure.com
$LabDeepSeekKey      = ""    # MaaS key (only if using key auth)
$LabDeepSeekModel    = ""    # e.g. DeepSeek-R1
