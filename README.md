# Sentinel AI Threat Report Agent

A custom **Microsoft Security Copilot** agent that investigates AI security threats — blocked requests, jailbreak attempts, and content filter violations on Azure OpenAI — and generates **executive-level reports** for CISO board presentations.

---

## What This Agent Does

When deployed in Security Copilot, the agent:

1. **Queries** Microsoft Sentinel for blocked AI requests, security alerts, and incidents via KQL
2. **Analyzes** attack patterns — burst detection, per-IP block ratios, hourly timelines
3. **Generates** structured executive reports with risk ratings and MITRE ATLAS mapping
4. **Recommends** prioritized defensive actions in plain language

### How It Runs

| Mode | Description |
|------|-------------|
| **Interactive** | Click "Chat with agent" in Security Copilot and ask questions in natural language |
| **Scheduled** | Start the trigger — polls every 5 minutes for new blocked requests and auto-generates reports |

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                  Microsoft Security Copilot                   │
│  ┌────────────────────────────────────────────────────────┐  │
│  │       Sentinel AI Threat Report Agent                  │  │
│  │           (Interactive Agent)                          │  │
│  │                                                        │  │
│  │  User Question ──► Orchestrator ──► Executive Report   │  │
│  └──────────┬──────────────┬──────────────────────────────┘  │
│             │              │                                  │
│     ┌───────┴───────┐  ┌──┴──────────────┐                   │
│     │  KQL Skills   │  │   KQL Skills    │                   │
│     │ (Diagnostics) │  │   (Sentinel)    │                   │
│     └───────┬───────┘  └──┬──────────────┘                   │
└─────────────┼─────────────┼──────────────────────────────────┘
              │             │
     ┌────────┴─────────────┴─────────┐
     │     Microsoft Sentinel         │
     │   Log Analytics Workspace      │
     │                                │
     │  AzureDiagnostics              │
     │  SecurityAlert                 │
     │  SecurityIncident              │
     └────────────────┬───────────────┘
                      │
     ┌────────────────┴───────────────┐
     │    Azure OpenAI Service        │
     │    Content Safety Filters      │
     │    Prompt Shields              │
     └────────────────────────────────┘
```

---

## Repository Structure

```
.
├── sentinel-ai-threat-report-agent.yaml   # Agent manifest — deploy this to Security Copilot
├── SETUP.md                               # Step-by-step deployment guide
├── tests/
│   ├── test-aml-t0065.ps1                 # MITRE ATLAS AML.T0065 attack simulation (21 tests)
│   └── test-jailbreak.ps1                 # Basic jailbreak validation (10 tests)
├── README.md
├── LICENSE
└── .gitignore
```

---

## Quick Start

### Prerequisites

| Requirement | Details |
|-------------|---------|
| **Security Copilot** | Active license with custom plugin permissions |
| **Microsoft Sentinel** | Workspace receiving Azure OpenAI diagnostic logs |
| **Azure OpenAI** | Deployed model with content safety filters enabled |
| **Permissions** | Security Reader on the Sentinel workspace |

### 1. Configure the manifest

Edit `sentinel-ai-threat-report-agent.yaml` and replace the placeholders in **every KQL skill** (6 skills):

```yaml
Settings:
  Target: Sentinel
  TenantId: '<your-tenant-id>'
  SubscriptionId: '<your-subscription-id>'
  ResourceGroupName: '<your-resource-group>'
  WorkspaceName: '<your-workspace-name>'
```

> **Tip:** Use find-and-replace. All 6 skills use the same 4 values.

### 2. Deploy to Security Copilot

1. Open [Security Copilot](https://securitycopilot.microsoft.com) → **Agents** → **Build**
2. Upload `sentinel-ai-threat-report-agent.yaml`
3. The agent appears under **Agents** as "Sentinel AI Threat Report Agent"
4. Click **Chat with agent** to start

### 3. Start the automatic trigger (optional)

1. Open the agent page → click **Run** (top-right dropdown)
2. Select **ScheduledBlockedRequestCheck**
3. The agent now polls every 5 minutes and auto-generates reports when blocked requests are found

> For the full walkthrough including diagnostic logging, Sentinel rules, and verification, see **[SETUP.md](SETUP.md)**.

---

## Agent Skills

| Skill | Type | Description |
|-------|------|-------------|
| `SentinelAIThreatReportEntrypoint` | Agent | Orchestrates queries and generates the executive report |
| `FetchNewBlockedAIRequests` | KQL | Trigger — checks for blocked requests in the last 5 min |
| `GetBlockedAIRequests` | KQL | All HTTP 400 blocked requests with IP, model, timestamp |
| `GetAIRequestSummaryByIP` | KQL | Per-IP breakdown: total, blocked, success, block ratio % |
| `GetAISecurityAlerts` | KQL | Sentinel alerts for AI/jailbreak/prompt keywords |
| `GetAISecurityIncidents` | KQL | Sentinel incidents with severity and status |
| `GetAIRequestTimeline` | KQL | Hourly breakdown for pattern analysis |

All query skills accept an optional `LookbackHours` parameter (default: 24).

---

## Starter Prompts

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
| Agent returns no data | Verify diagnostic logging is enabled and logs flow to the workspace |
| "No results found" | Try a larger `LookbackHours` (e.g., `168` for 7 days) |
| KQL errors | Ensure `AzureDiagnostics` and `SecurityAlert` tables exist in your workspace |
| Upload fails | Validate YAML syntax — `Name` fields cannot contain spaces or special characters |
| Auth error | Your account needs **Security Reader** on the Sentinel workspace |

---

## Extra Resources: Attack Simulation Scripts

These companion scripts validate your AI security detection pipeline by simulating real attack techniques. They are **not required** for the agent — they generate the blocked requests and alerts that the agent reports on.

### tests/test-aml-t0065.ps1 — MITRE ATLAS Full Simulation

Simulates **21 attack techniques** across all sub-techniques of [AML.T0065 (LLM Prompt Injection)](https://atlas.mitre.org/techniques/AML.T0065):

| Sub-technique | Tests | Examples |
|---------------|-------|----------|
| Direct Prompt Injection (AML.T0065.000) | 6 | System override, instruction injection, prompt leak |
| Indirect Prompt Injection (AML.T0065.001) | 4 | Hidden instructions, data exfil via summarization |
| LLM Jailbreak (AML.T0065.002) | 10 | DAN, Evil Confidant, translation bypass, Base64 encoding |
| Baseline | 1 | Normal question to verify the model works |

```powershell
# Requires: Azure CLI logged in, Cognitive Services User role
.\tests\test-aml-t0065.ps1
```

Expected: ~12 BLOCKED, ~4 REFUSED, ~2 PASSED, ~2 rate-limited (~84% detection).

### tests/test-jailbreak.ps1 — Quick Validation

A simpler **10-test** script for fast smoke testing:

```powershell
.\tests\test-jailbreak.ps1
```

> **Warning:** These scripts are for authorized testing only. Only run them against resources you own.

---

## Sentinel Analytics Rules

These companion rules create the alerts and incidents the agent reports on. See [SETUP.md](SETUP.md) for deployment commands.

| Rule | Severity | Triggers When |
|------|----------|---------------|
| AI Jailbreak Attempt Detected | Medium | >3 blocked requests from same IP in 24h |
| AI Brute-Force Jailbreak Detected | High | >10 blocked requests from same IP in 1h |
| AI High Block Ratio Detected | Medium | >50% block rate with ≥5 total requests |

---

## License

MIT — see [LICENSE](LICENSE).

---

## References

- [Security Copilot Agent Manifest](https://learn.microsoft.com/en-us/copilot/security/developer/agent-manifest)
- [Build Interactive Agents](https://learn.microsoft.com/en-us/copilot/security/developer/build-interactive-agents)
- [MITRE ATLAS AML.T0065](https://atlas.mitre.org/techniques/AML.T0065)
- [Azure OpenAI Content Safety](https://learn.microsoft.com/en-us/azure/ai-services/openai/concepts/content-filter)
