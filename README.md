# AI Jailbreak & Sentinel 101

A hands-on workshop for testing Azure OpenAI content safety filters, simulating MITRE ATLAS attacks, detecting threats with Microsoft Sentinel, and reporting with Security Copilot.

> **Purpose:** Learn how AI jailbreak attacks work, how Azure defends against them, and how to build a full detection-and-response pipeline — from content filters to Sentinel alerts to executive reports.

---

## What You'll Learn

| Module | What You Do | What You Learn |
|--------|-------------|----------------|
| **1. Attack Simulation** | Run jailbreak prompts against Azure OpenAI | How content safety filters block prompt injection, DAN, role-play, and obfuscation attacks |
| **2. Detection Pipeline** | Connect Azure OpenAI logs to Microsoft Sentinel | How diagnostic settings, Defender for AI, and analytics rules create a layered detection system |
| **3. Threat Investigation** | Query Sentinel with KQL hunting queries | How to correlate blocked requests, security alerts, and MITRE ATLAS techniques |
| **4. Executive Reporting** | Deploy a Security Copilot agent | How to auto-generate board-level AI threat reports from Sentinel data |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Detection Pipeline                           │
│                                                                  │
│  ┌──────────────┐    Diagnostic     ┌────────────────────────┐  │
│  │ Azure OpenAI │───Settings────────│  Microsoft Sentinel    │  │
│  │ + Content    │    (Audit,        │  (Log Analytics)       │  │
│  │   Safety     │    RequestResponse│                        │  │
│  │   Filters    │    Trace)         │  AzureDiagnostics      │  │
│  └──────┬───────┘                   │  SecurityAlert         │  │
│         │                           │  SecurityIncident      │  │
│         │  Defender    ┌──────────┐ │                        │  │
│         └──for AI──────│ Defender │─│  Analytics Rules (KQL) │  │
│                        │ for Cloud│ │  Hunting Queries       │  │
│                        └──────────┘ └───────────┬────────────┘  │
│                                                 │               │
│                                     ┌───────────┴────────────┐  │
│                                     │  Security Copilot      │  │
│                                     │  Threat Report Agent   │  │
│                                     └────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Repository Structure

```
.
├── README.md                                  # This file
├── SETUP.md                                   # Deployment guide (diagnostic settings, Sentinel, Defender)
├── TESTING.md                                 # How to run tests and interpret results
├── WORKSHOP.md                                # Step-by-step workshop guide for facilitators
├── NEW-TENANT-SETUP.md                        # Provision a brand-new lab tenant from scratch
├── lab.config.example.ps1                     # Config template — copy to lab.config.ps1
├── sentinel-ai-threat-report-agent.yaml       # Security Copilot agent manifest
├── setup/
│   └── deploy-lab.ps1                         # Validates config and checks connectivity
├── tests/
│   ├── test-jailbreak.ps1                     # Quick 10-test smoke test (~2 min)
│   ├── test-aml-t0065.ps1                     # Full MITRE ATLAS AML.T0065 simulation (21 tests, ~4 min)
│   ├── test-bypass-analysis.ps1               # Deep filter-bypass analysis (18 tests)
│   └── test-consistency.ps1                   # Consistency test — 60 calls across 6 attack patterns
├── hunting/
│   ├── ai-alerts-mitre-correlation.kql        # KQL hunting query — correlate alerts with MITRE tactics
│   └── deploy-analytics-rules.ps1             # Deploy 4 custom Sentinel analytics rules
├── playbooks/
│   └── Tag-AI-Threat-On-Jailbreak/            # Logic App playbook for auto-tagging incidents
│       ├── azuredeploy.json                   # ARM template
│       ├── automation-rule-body.json           # Automation rule config
│       └── README.md                          # Playbook documentation
├── docs/                                      # HTML reports generated during the lab
├── logs/                                      # Test result logs (gitignored)
├── LICENSE                                    # MIT
└── .github/
    └── copilot-instructions.md                # GitHub Copilot workspace instructions
```

---

## Quick Start

### Prerequisites

| Requirement | Details |
|-------------|---------|
| **Azure subscription** | With Azure OpenAI deployed (any GPT-4 class model) |
| **Microsoft Sentinel** | Log Analytics workspace with Sentinel enabled |
| **Azure CLI** | v2.60+ — logged in to the correct tenant |
| **PowerShell** | 5.1+ or 7+ |
| **RBAC roles** | Cognitive Services User (OpenAI) + Security Reader (Sentinel) |
| **Security Copilot** *(optional)* | For the executive report agent (Module 4) |

### 1. Clone and configure

```powershell
git clone https://github.com/<your-org>/ai-jailbreak-sentinel-101.git
cd ai-jailbreak-sentinel-101

# Create your config from the template
Copy-Item lab.config.example.ps1 lab.config.ps1
```

Edit `lab.config.ps1` with your Azure resource values — or ask GitHub Copilot to do it:

> *"Configure the lab — discover my Azure OpenAI and Sentinel resources and fill in lab.config.ps1"*

### 2. Validate connectivity

```powershell
.\setup\deploy-lab.ps1
```

### 3. Run your first attack simulation

```powershell
# Quick smoke test (10 tests, ~2 min)
.\tests\test-jailbreak.ps1

# Full MITRE ATLAS simulation (21 tests, ~4 min)
.\tests\test-aml-t0065.ps1
```

### 4. Investigate in Sentinel

Wait 10-15 minutes for logs, then run the hunting query in your Sentinel workspace:

```kql
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| where ResultSignature == "400"
| summarize BlockedCount = count() by CallerIPAddress, bin(TimeGenerated, 1h)
```

> For the full walkthrough, see [WORKSHOP.md](WORKSHOP.md). For facilitator setup, see [NEW-TENANT-SETUP.md](NEW-TENANT-SETUP.md).

---

## Test Scripts

### `test-jailbreak.ps1` — Quick Smoke Test

10 prompts covering the most common jailbreak patterns. Runs in ~2 minutes.

| Expected Results | Count |
|------------------|-------|
| BLOCKED (content filter) | ~6 |
| REFUSED (model declined) | ~2 |
| PASSED (baselines) | 2 |

### `test-aml-t0065.ps1` — MITRE ATLAS Simulation

21 attack techniques across all sub-techniques of [AML.T0065 (LLM Prompt Injection)](https://atlas.mitre.org/techniques/AML.T0065):

| Sub-technique | Tests | Examples |
|---------------|-------|----------|
| Direct Prompt Injection (AML.T0065.000) | 6 | System override, instruction injection, prompt leak |
| Indirect Prompt Injection (AML.T0065.001) | 4 | Hidden instructions, data exfil via summarization |
| LLM Jailbreak (AML.T0065.002) | 10 | DAN, Evil Confidant, translation bypass, Base64 encoding |
| Baseline | 1 | Normal question |

### `test-bypass-analysis.ps1` — Deep Filter-Bypass Analysis

18 tests that probe the 6 attacks that bypass the content filter (HTTP 200) but get refused by the model's RLHF training. Tests original, aggressive, and subtle variants of each.

### `test-consistency.ps1` — Consistency Assessment

60 API calls across 6 attack patterns (10 runs each) to measure how consistently filters block each technique. Outputs JSON results for analysis.

> See [TESTING.md](TESTING.md) for detailed result interpretation and troubleshooting.

---

## Sentinel Detection

### Analytics Rules

Deploy 4 custom rules that detect bypass patterns the content filter misses:

```powershell
.\hunting\deploy-analytics-rules.ps1
```

| Rule | Severity | Detects |
|------|----------|---------|
| Educational Framing Attack | Medium | Academic/research framing used to bypass filters |
| Creative Writing Attack | Medium | Fiction/roleplay framing to extract harmful content |
| Rapid Probing Detection | High | >5 distinct attack techniques from same IP in 1 hour |
| Output Content Analysis | High | Known attack tool names in model responses |

### Hunting Query

`hunting/ai-alerts-mitre-correlation.kql` — correlates blocked request volumes with MITRE ATLAS techniques and Defender for AI alerts.

### Playbook

`playbooks/Tag-AI-Threat-On-Jailbreak/` — Logic App that auto-tags Sentinel incidents with AI threat metadata. Deploy via the ARM template.

---

## Security Copilot Agent

The `sentinel-ai-threat-report-agent.yaml` manifest deploys a custom agent that generates executive-level AI threat reports from Sentinel data.

### Agent Skills

| Skill | Type | Description |
|-------|------|-------------|
| `SentinelAIThreatReportEntrypoint` | Agent | Orchestrates queries and generates the executive report |
| `FetchNewBlockedAIRequests` | KQL | Trigger — checks for blocked requests in the last 5 min |
| `GetBlockedAIRequests` | KQL | All HTTP 400 blocked requests with IP, model, timestamp |
| `GetAIRequestSummaryByIP` | KQL | Per-IP breakdown: total, blocked, success, block ratio % |
| `GetAISecurityAlerts` | KQL | Sentinel alerts for AI/jailbreak/prompt keywords |
| `GetAISecurityIncidents` | KQL | Sentinel incidents with severity and status |
| `GetAIRequestTimeline` | KQL | Hourly breakdown for pattern analysis |

### Deploy the Agent

1. Edit `sentinel-ai-threat-report-agent.yaml` — replace the 4 placeholder values in every KQL skill's `Settings`
2. Open [Security Copilot](https://securitycopilot.microsoft.com) → **Agents** → **Build**
3. Upload the YAML file
4. Click **Chat with agent** and try: *"Generate an executive report on all blocked AI requests in the last 24 hours"*

### Starter Prompts

| Prompt | Audience |
|--------|----------|
| *"Generate an executive report on all blocked AI requests in the last 24 hours"* | CISO, SOC |
| *"Show me a summary of AI jailbreak attempts detected this week"* | CISO, SOC |
| *"Analyze the risk level of recent AI content filter violations and recommend mitigations"* | CISO, Threat Intel |
| *"List all high-severity AI security alerts from Sentinel in the last 7 days"* | SOC, Threat Intel |

---

## Report Format

The agent produces structured reports:

| Section | Content |
|---------|---------|
| **Executive Summary** | 2-3 sentence overview (under 100 words) |
| **Key Findings** | Bullet points with numbers |
| **Risk Assessment** | LOW / MEDIUM / HIGH / CRITICAL with explanation |
| **Attack Analysis** | Plain-English description mapped to MITRE ATLAS |
| **Recommendations** | Prioritized action items with urgency |
| **Appendix** | Raw data tables for the security team |

### Sample Output

> **Executive Summary**
> In the past 24 hours, 20 AI requests were blocked by Azure content safety filters, all from a single IP address. The attack shows a concentrated burst of prompt injection attempts within a 4-minute window, indicating systematic probing of AI defenses.
>
> **Risk Assessment: HIGH**
> The 47.6% block ratio and burst pattern indicate deliberate adversarial testing of the AI model's safety guardrails.

---

## Customization

### Change the Sentinel workspace

Replace these 4 values in every KQL skill's `Settings`:

| Field | Description |
|-------|-------------|
| `TenantId` | Entra ID tenant ID |
| `SubscriptionId` | Azure subscription containing Sentinel |
| `ResourceGroupName` | Resource group of the Log Analytics workspace |
| `WorkspaceName` | Log Analytics / Sentinel workspace name |

### Add a new KQL skill

Add an entry under `Format: KQL` in SkillGroups, then add its name to `ChildSkills` in `SentinelAIThreatReportEntrypoint`. See the existing skills as templates.

### Modify the report format

Edit the `Instructions` field in the agent's Settings section. Update the `# Report Format` section to change headings, sections, or tone.

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `lab.config.ps1 not found` | Copy from `lab.config.example.ps1` |
| Agent returns no data | Verify diagnostic logging is enabled and logs flow to the workspace |
| "No results found" in Copilot | Try a larger `LookbackHours` (e.g., `168` for 7 days) |
| KQL errors | Ensure `AzureDiagnostics` and `SecurityAlert` tables exist in your workspace |
| Analytics rules fail to deploy | Run tests first — rules need `AzureDiagnostics` table to exist (takes 10-15 min after first log) |
| Tests return 401 | Check `az login` and Cognitive Services User role |
| Tests return 429 | Rate limited — wait 60 seconds and re-run |

---

## Disclaimer

These scripts are for **authorized security testing only**. Only run them against Azure OpenAI resources you own or have explicit permission to test. The attack simulations are designed to validate defensive controls, not to cause harm.

---

## License

MIT — see [LICENSE](LICENSE).

---

## References

- [MITRE ATLAS AML.T0065 — LLM Prompt Injection](https://atlas.mitre.org/techniques/AML.T0065)
- [Azure OpenAI Content Safety](https://learn.microsoft.com/en-us/azure/ai-services/openai/concepts/content-filter)
- [Microsoft Defender for AI](https://learn.microsoft.com/en-us/azure/defender-for-cloud/ai-threat-protection)
- [Microsoft Sentinel Documentation](https://learn.microsoft.com/en-us/azure/sentinel/)
- [Security Copilot Agent Manifest](https://learn.microsoft.com/en-us/copilot/security/developer/agent-manifest)
- [Azure OpenAI Diagnostic Logging](https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/monitoring)
