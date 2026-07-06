# NexaFlow Skill / Agent / MCP Pack

This pack turns NexaFlow's analysis knowledge into reusable project assets that can be called from other AI tools without changing the NexaFlow macOS app.

## What Is Included

### Skills

Skills live in `skills/nexaflow/`.

| Skill | Use it for |
|---|---|
| `financial-product-analysis` | Overseas fintech product and operations analysis |
| `kpi-reporting` | Complete reports, concise reports, WBR/MBR-style updates |
| `metric-diagnostics` | Metric movements, anomalies, funnel breaks |
| `data-ingestion-semantics` | Local file, Tableau, Jira, DingTalk, Confluence source semantics |
| `table-period-and-quality` | Table shape, period candidates, quality risks |
| `external-evidence-research` | External evidence coverage, timing, weak-signal boundaries |
| `smart-memory-correction` | Correction memory and report exclusion rules |
| `notebook-sql-evidence` | Safe SQL/Notebook evidence planning |
| `business-space-modeling` | Business space, business map, domain roles |
| `markdown-table-rendering` | Readable chat/report/Word table rendering |
| `connector-troubleshooting` | Tableau/Jira/DingTalk/Confluence error diagnosis |
| `financial-risk-compliance-boundary` | Financial risk, compliance, investment, KYC, and collection boundaries |
| `app-ux-product-ops` | Product/operations user flows, report scope, and UX wording |

### Agents

Agent playbooks live in `agents/nexaflow/`.

| Agent | Role |
|---|---|
| `data-acquisition-agent` | Plan connector setup and data acquisition semantics |
| `analysis-prep-agent` | Build structured context before analysis |
| `financial-analysis-agent` | Answer product/operations questions |
| `report-agent` | Generate complete or concise report briefs |
| `evidence-audit-agent` | Audit output support and evidence quality |
| `memory-curator-agent` | Manage correction and preference memory |
| `connector-sync-agent` | Plan connector sync and interpret failures |
| `quality-guard-agent` | Check safety, scope, evidence, and formatting |
| `orchestrator-agent` | Select the right agent chain for a task |
| `report-scope-agent` | Decide which user questions enter reports |
| `connector-debug-agent` | Diagnose connector setup and sync errors |
| `tableau-import-advisor-agent` | Explain Tableau View/Worksheet import limits |

The Agent registry lives at `agents/nexaflow/registry.json`.

## MCP Server

The MCP server lives in `mcp/nexaflow-mcp/`. It is a TypeScript stdio server with no npm dependencies. It is read-only and does not trigger NexaFlow App actions.

### Start

```bash
cd /Users/WilliamChang/Documents/Playground/IterationPilot/mcp/nexaflow-mcp
npm run start
```

### Codex / Claude Desktop Command

```json
{
  "command": "node",
  "args": [
    "--experimental-strip-types",
    "/Users/WilliamChang/Documents/Playground/IterationPilot/mcp/nexaflow-mcp/src/server.ts"
  ]
}
```

## MCP Tools

| Tool | Purpose |
|---|---|
| `list_nexaflow_skills` | List available NexaFlow skills |
| `get_nexaflow_skill` | Read a skill's `SKILL.md` |
| `search_nexaflow_skills` | Search skills by keyword |
| `list_nexaflow_agents` | List available agent playbooks |
| `get_nexaflow_agent` | Read an agent's `AGENT.md` |
| `search_nexaflow_agents` | Search agents by task keyword |
| `run_agent_playbook` | Generate a structured read-only output from an agent playbook |
| `build_handoff_packet` | Build an agent-to-agent handoff packet |
| `get_context_contract_schema` | Return shared context JSON contracts |
| `build_financial_analysis_brief` | Build a structured analysis brief |
| `build_report_brief` | Build a complete/concise report brief |
| `validate_financial_analysis_output` | Check facts/inferences/hypotheses/missing-data and percentage formatting |
| `validate_skill_agent_pack` | Validate Skill/Agent pack structure |
| `get_connector_error_help` | Map connector errors to likely causes and next steps |
| `classify_user_question_for_report` | Decide whether a question belongs in a report |
| `explain_connector_setup` | Explain setup fields for Tableau/Jira/DingTalk/Confluence |
| `build_connector_sync_checklist` | Build a safe pre-sync checklist |

## MCP Resources

| Resource | Purpose |
|---|---|
| `nexaflow://skills/{skillName}` | Skill instructions |
| `nexaflow://agents/{agentName}` | Agent playbook |
| `nexaflow://agents/registry` | Agent registry |
| `nexaflow://templates/{templateName}` | Analysis/report brief templates |
| `nexaflow://checklists/{checklistName}` | Audit/setup checklists |
| `nexaflow://schemas/context-contracts` | Shared JSON context contracts |
| `nexaflow://policies/financial-prompt-policy` | Financial output policy |
| `nexaflow://examples/report-brief` | Example report brief |

## Install Helpers

Project-local skills can be copied into Codex's discoverable skill folder with:

```bash
cd /Users/WilliamChang/Documents/Playground/IterationPilot
./script/install_nexaflow_skills.sh
./script/install_nexaflow_skills.sh --apply
```

The first command is a dry run. The second command copies skills to `${CODEX_HOME:-$HOME/.codex}/skills/nexaflow-*`.

Use `./script/quick_validate.py` to validate Skill/Agent structure.

## Safety Boundary

First version is intentionally read-only.

It does not:

- Open or control the NexaFlow app.
- Read user tokens or secrets.
- Sync Jira, DingTalk, Tableau, Confluence, local folders, or external sources.
- Import files or Tableau views.
- Trigger AI analysis or report generation.
- Modify workspace files through MCP tools.

## Future v2 Extension

If NexaFlow needs writable MCP tools later, design them separately with explicit confirmation, credential isolation, operation logs, business-space scope, and cancellation:

- `sync_connector`
- `import_tableau_view`
- `create_analysis_task`
- `run_deep_analysis`
- `generate_complete_report`
- `generate_concise_report`

Those are intentionally excluded from v1.
