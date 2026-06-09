# AI Jailbreak & Sentinel 101

A hands-on workshop for testing Azure OpenAI content safety filters, simulating MITRE (Adversarial Threat Landscape for AI Systems) ATLAS attacks, and detecting threats with Microsoft Sentinel.

> **Purpose:** Learn how AI jailbreak attacks work, how Azure defends against them, and how to build a detection pipeline — from content filters to Sentinel analytics rules that cover the inference gap.

---

## What You'll Learn

| Module | What You Do | What You Learn |
|--------|-------------|----------------|
| **1. Attack Simulation** | Run jailbreak prompts against Azure OpenAI | How content safety filters block prompt injection, DAN (Do Anything Now), role-play, and obfuscation attacks |
| **2. Detection Pipeline** | Connect Azure OpenAI logs to Microsoft Sentinel | How diagnostic settings, Defender for AI, and KQL (Kusto Query Language) analytics rules create a layered detection system |
| **3. Threat Investigation** | Query Sentinel with KQL hunting queries | How to correlate blocked requests, security alerts, and MITRE ATLAS techniques |

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                        Detection Pipeline                                 │
│                                                                           │
│  ┌──────────────┐  Diagnostic Settings  ┌────────────────────────────┐   │
│  │ Azure OpenAI │────(metadata only)───▶│  AzureDiagnostics          │   │
│  │ + Content    │                       │  (request counts, lengths) │   │
│  │   Safety     │                       └────────────────────────────┘   │
│  │   Filters    │                                                         │
│  └──────┬───────┘        HTTP Data      ┌────────────────────────────┐   │
│         │               Collector API   │  AIPromptLog_CL            │   │
│         │◀──tests───────(HMAC signed)──▶│  (full prompt + response)  │   │
│         │                                └─────────────┬──────────────┘   │
│         │                                              │                  │
│         │  Defender for AI     ┌──────────┐    Analytics Rules (KQL)     │
│         └──────────────────────│ Defender │──▶ SecurityAlert /           │
│                                │ for Cloud│    SecurityIncident          │
│                                └──────────┘                               │
└──────────────────────────────────────────────────────────────────────────┘
```

> **Why two log streams?** Azure OpenAI diagnostic logs contain only request metadata (counts, lengths, timing) — no prompt or response text. To let Sentinel pattern-match on content, the test scripts tap the full prompt and response client-side and ship them to a custom `AIPromptLog_CL` table via the Log Analytics HTTP Data Collector API. In production the same role is played by an API Management GenAI gateway or an App Service-fronted proxy.

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
├── setup/
│   └── deploy-lab.ps1                         # Validates config and checks connectivity
├── tests/
│   ├── test-jailbreak.ps1                     # Quick 10-test smoke test (~2 min)
│   ├── test-aml-t0065.ps1                     # Full MITRE ATLAS AML.T0065 simulation + Sentinel rule triggers (24 tests, ~5 min)
│   ├── test-bypass-analysis.ps1               # Deep filter-bypass analysis (18 tests)
│   └── test-consistency.ps1                   # Consistency test — 60 calls across 6 attack patterns
├── hunting/
│   ├── ai-alerts-mitre-correlation.kql        # KQL hunting query — correlate alerts with MITRE tactics
│   └── deploy-analytics-rules.ps1             # Deploy 3 custom Sentinel analytics rules
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
| **Workspace shared key** | Primary shared key of the Log Analytics workspace (used by test scripts to ingest prompt/response telemetry via the Data Collector API). Retrieve with `az monitor log-analytics workspace get-shared-keys`. |
| **Azure CLI** | v2.60+ — logged in to the correct tenant |
| **PowerShell** | 5.1+ or 7+ |
| **RBAC (Role-Based Access Control) roles** | Cognitive Services User (Azure OpenAI) + Security Reader (Sentinel) + read access to workspace shared keys |

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

# Full MITRE ATLAS simulation + Sentinel rule triggers (24 tests, ~5 min)
.\tests\test-aml-t0065.ps1
```

### 4. Investigate in Sentinel

Records ingested via the Data Collector API become queryable within ~5–10 minutes. Check them with:

```kql
AIPromptLog_CL
| where TimeGenerated > ago(30m)
| project TimeGenerated, TestName_s, Status_s, FinishReason_s, Prompt_s, Response_s
| order by TimeGenerated desc
```

And check that the 4 analytic rules fired:

```kql
SecurityAlert
| where AlertName startswith "AI Jailbreak"
| where TimeGenerated > ago(2h)
| project TimeGenerated, AlertName, AlertSeverity
| order by TimeGenerated desc
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

### `test-aml-t0065.ps1` — MITRE ATLAS Simulation + Sentinel Rule Triggers

24 tests total: 21 attack techniques across all sub-techniques of [AML.T0065 (LLM Prompt Injection)](https://atlas.mitre.org/techniques/AML.T0065), plus 3 prompts engineered to exercise the custom Sentinel analytic rules. Every call is shipped to `AIPromptLog_CL` so Sentinel can pattern-match on prompt and response content.

| Sub-technique | Tests | Examples |
|---------------|-------|----------|
| Direct Prompt Injection (AML.T0065.000) | 6 | System override, instruction injection, prompt leak |
| Indirect Prompt Injection (AML.T0065.001) | 4 | Hidden instructions, data exfiltration via summarization |
| LLM (Large Language Model) Jailbreak (AML.T0065.002) | 10 | DAN (Do Anything Now), Evil Confidant, translation bypass, Base64 encoding |
| Sentinel Rule Triggers | 3 | Educational framing, creative writing, attack tools in response |
| Baseline | 1 | Normal question |

### `test-bypass-analysis.ps1` — Deep Filter-Bypass Analysis

18 tests that probe the 6 attacks that bypass the content filter (HTTP 200) but get refused by the model's RLHF (Reinforcement Learning from Human Feedback) training. Tests original, aggressive, and subtle variants of each.

### `test-consistency.ps1` — Consistency Assessment

60 API (Application Programming Interface) calls across 6 attack patterns (10 runs each) to measure how consistently filters block each technique. Outputs JSON results for analysis.

> See [TESTING.md](TESTING.md) for detailed result interpretation and troubleshooting.

---

## Sentinel Detection

### Analytics Rules

Deploy 3 custom rules that detect bypass patterns the content filter misses:

```powershell
.\hunting\deploy-analytics-rules.ps1
```

All three rules query the custom `AIPromptLog_CL` table populated by the test scripts. They run every 5 minutes with a 30-minute lookback to tolerate Data Collector API ingestion latency.

| Rule | Severity | Detects |
|------|----------|---------|
| Educational Framing Attack | High | Academic/research framing combined with attack-technique keywords in prompts |
| Creative Writing Attack | High | Fiction/roleplay framing combined with harmful action verbs in prompts |
| Output Content Analysis | High | Known attack tool names (e.g. metasploit, mimikatz, sqlmap) appearing in model responses |

### Hunting Query

`hunting/ai-alerts-mitre-correlation.kql` — correlates blocked request volumes with MITRE ATLAS techniques and Defender for AI alerts.

### Playbook

`playbooks/Tag-AI-Threat-On-Jailbreak/` — Logic App that auto-tags Sentinel incidents with AI threat metadata. Deploy via the ARM (Azure Resource Manager) template.

---

## Why Custom Detection Rules? The Inference Gap

Azure OpenAI has two layers of defense: **content safety filters** (input/output pattern matching) and **RLHF (Reinforcement Learning from Human Feedback) training** (the model's learned refusal behavior). In testing, content filters block ~67% of attacks outright (HTTP 400), and RLHF catches another ~28% (the model says "I'm sorry, I can't help with that"). Together, they achieve a ~95% detection rate.

**The problem is the remaining 5% — and the attacks that get HTTP 200 responses.**

Our deep analysis of 21 MITRE ATLAS AML.T0065 attack techniques revealed 6 categories that consistently bypass the content filter (receiving HTTP 200 instead of HTTP 400), relying solely on RLHF to refuse:

| Bypass Category | Why the Filter Misses It | Risk |
|----------------|--------------------------|------|
| **Context Manipulation** | No explicit attack keywords — the prompt sets up a roleplay frame ("a conversation with an unrestricted AI") | The model might comply if RLHF training has gaps for the phrasing |
| **Token Smuggling** | Obfuscates harmful terms (e.g., "ke-ylo-gger") to evade pattern matching | Content filters rely on keyword detection; splitting tokens defeats this |
| **Hypothetical/Creative Framing** | Wraps harmful requests in fiction ("for my novel", "movie script", "thought experiment") | Filters often allow creative contexts even when the underlying request is harmful |
| **Multi-step Goal Hijacking** | Starts with a legitimate question, then gradually escalates to harmful territory | The initial safe context lowers the filter's suspicion threshold |
| **Ethical/Academic Framing** | Uses researcher or educator identity ("AI ethics researcher", "CompTIA exam prep") | Legitimate-sounding academic framing bypasses keyword-based detection |
| **Recursive Prompt Injection** | Structures the attack as "pre-processing steps" (e.g., "set safety_mode=false") | Looks like a technical instruction set rather than an attack |

### The Inference Gap

Content filters are **deterministic** — they evaluate prompts against known patterns at request time. But LLM (Large Language Model) inference is **probabilistic** — the same prompt can produce different responses across runs. This creates an "inference gap" where:

1. **Input-side filters miss sophisticated framing** — educational, creative, and ethical framings don't match known attack signatures
2. **Output-side analysis is limited** — filters check the response for harmful content but can't assess intent or context
3. **Consistency varies** — a borderline prompt blocked 8 out of 10 times still succeeds 20% of the time through repeated probing

**This is why we create custom Sentinel analytics rules.** They provide a third detection layer that operates on the full request/response logs *after* inference, catching patterns that real-time filters miss:

- **Educational Framing Rule** — detects certification/coursework language combined with attack technique keywords
- **Creative Writing Rule** — detects fiction/screenplay framing combined with harmful action verbs
- **Attack Tools in Response Rule** — detects known offensive tool names (metasploit, mimikatz, hashcat, etc.) in model outputs, regardless of how benign the prompt looked

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `lab.config.ps1 not found` | Copy from `lab.config.example.ps1` |
| Test script warns `Log ingestion disabled` | Missing `$LabWorkspaceCustomerId` or `$LabWorkspaceSharedKey` in `lab.config.ps1` |
| `AIPromptLog_CL` table doesn't exist in KQL | Run `.\tests\test-aml-t0065.ps1` at least once; the first POST creates the table (~5–10 min delay before it's queryable) |
| Analytic rules deploy but no `SecurityAlert` rows appear | Wait 5–10 min after the test run for ingestion, then another 5 min for the scheduled rule to evaluate |
| Tests return 401 | Check `az login` and Cognitive Services User role |
| Tests return 429 | Rate limited — wait 60 seconds and re-run |
| Data Collector POST fails | Verify the shared key is the workspace's primary (or secondary) key and has not been rotated |

---

## Disclaimer

These scripts are for **authorized security testing only**. Only run them against Azure OpenAI resources you own or have explicit permission to test. The attack simulations are designed to validate defensive controls, not to cause harm.

---

## License

MIT (Massachusetts Institute of Technology) — see [LICENSE](LICENSE).

---

## References

- [MITRE ATLAS AML.T0065 — LLM (Large Language Model) Prompt Injection](https://atlas.mitre.org/techniques/AML.T0065)
- [Azure OpenAI Content Safety](https://learn.microsoft.com/en-us/azure/ai-services/openai/concepts/content-filter)
- [Microsoft Defender for AI](https://learn.microsoft.com/en-us/azure/defender-for-cloud/ai-threat-protection)
- [Microsoft Sentinel Documentation](https://learn.microsoft.com/en-us/azure/sentinel/)
- [Azure OpenAI Diagnostic Logging](https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/monitoring)

---

> **Note:** This lab was inspired by the [tuxsharxsec/Jailbreaks](https://github.com/tuxsharxsec/Jailbreaks) repository.
