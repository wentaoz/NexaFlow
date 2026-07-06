#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import readline from "node:readline";
import { fileURLToPath } from "node:url";

type JsonValue = null | boolean | number | string | JsonValue[] | { [key: string]: JsonValue };
type JsonObject = { [key: string]: JsonValue };

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const projectRoot = path.resolve(__dirname, "../../..");
const skillsRoot = path.join(projectRoot, "skills", "nexaflow");
const agentsRoot = path.join(projectRoot, "agents", "nexaflow");
const sharedRoot = path.join(skillsRoot, "_shared");

const skillDescriptions: Record<string, string> = {
  "financial-product-analysis": "Analyze overseas fintech product and operations questions with evidence.",
  "kpi-reporting": "Create complete and concise NexaFlow operating reports.",
  "metric-diagnostics": "Diagnose KPI movements, funnel breaks, and metric anomalies.",
  "data-ingestion-semantics": "Explain what each NexaFlow connector reads and means.",
  "table-period-and-quality": "Inspect table shape, period candidates, and quality risks.",
  "external-evidence-research": "Evaluate external evidence timing, scope, and attribution limits.",
  "smart-memory-correction": "Apply correction memory, definitions, and report exclusions.",
  "notebook-sql-evidence": "Plan safe SQL and Notebook evidence for verified analysis.",
  "business-space-modeling": "Model business spaces, maps, and fintech domain roles.",
  "markdown-table-rendering": "Render AI markdown tables into readable chat, report, and Word tables.",
  "connector-troubleshooting": "Troubleshoot Tableau, Jira, DingTalk, Confluence, local folder, and external source errors.",
  "financial-risk-compliance-boundary": "Check fintech risk, compliance, investment, KYC, underwriting, and collection boundaries.",
  "app-ux-product-ops": "Design NexaFlow user flows and wording for product managers and operations users."
};

const agentDescriptions: Record<string, string> = {
  "data-acquisition-agent": "Plan local, Tableau, Jira, DingTalk, Confluence, and external source setup.",
  "analysis-prep-agent": "Prepare structured context before analysis or report generation.",
  "financial-analysis-agent": "Answer fintech product and operations questions.",
  "report-agent": "Generate complete and concise report briefs.",
  "evidence-audit-agent": "Audit whether outputs are supported by data and evidence.",
  "memory-curator-agent": "Extract and apply correction and preference memory.",
  "connector-sync-agent": "Plan connector sync and interpret setup failures.",
  "quality-guard-agent": "Check output safety, scope, evidence, and formatting.",
  "orchestrator-agent": "Choose the right NexaFlow agent chain for a task.",
  "report-scope-agent": "Select which user questions enter a complete or concise report.",
  "connector-debug-agent": "Diagnose connector setup and sync errors safely.",
  "tableau-import-advisor-agent": "Advise Tableau View/Worksheet imports and analysis limitations."
};

const templateFiles: Record<string, string> = {
  "analysis-brief-template": path.join(sharedRoot, "templates", "analysis-brief-template.md"),
  "complete-report-brief-template": path.join(sharedRoot, "templates", "complete-report-brief-template.md"),
  "concise-report-brief-template": path.join(sharedRoot, "templates", "concise-report-brief-template.md")
};

const checklistFiles: Record<string, string> = {
  "evidence-audit-checklist": path.join(sharedRoot, "checklists", "evidence-audit-checklist.md"),
  "connector-setup-checklist": path.join(sharedRoot, "checklists", "connector-setup-checklist.md")
};

const connectorRequirements: Record<string, string[]> = {
  tableau: [
    "Tableau Base URL",
    "Site Content URL",
    "PAT Name",
    "PAT Token",
    "Project / Workbook / View filter if needed",
    "Download or crosstab export permission"
  ],
  jira: [
    "Jira Base URL",
    "Auth type: Jira Cloud API Token or Data Center PAT Bearer",
    "Email or username when using Jira Cloud",
    "Token",
    "Project Key",
    "Optional JQL, defaulting to recent project changes"
  ],
  dingtalk: [
    "Client ID",
    "Client Secret",
    "AgentId",
    "operatorId",
    "Folder link or folder ID with Space ID",
    "Document/table read permissions"
  ],
  confluence: [
    "Base URL",
    "Bearer token",
    "Root IDs",
    "Title keywords",
    "Max pages"
  ]
};

const tools = [
  {
    name: "list_nexaflow_skills",
    description: "List NexaFlow reusable skills.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false }
  },
  {
    name: "get_nexaflow_skill",
    description: "Read a NexaFlow skill SKILL.md by name.",
    inputSchema: {
      type: "object",
      properties: { skillName: { type: "string" } },
      required: ["skillName"],
      additionalProperties: false
    }
  },
  {
    name: "search_nexaflow_skills",
    description: "Search NexaFlow skills by keyword.",
    inputSchema: {
      type: "object",
      properties: { query: { type: "string" }, limit: { type: "number" } },
      required: ["query"],
      additionalProperties: false
    }
  },
  {
    name: "list_nexaflow_agents",
    description: "List NexaFlow agent playbooks.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false }
  },
  {
    name: "get_nexaflow_agent",
    description: "Read a NexaFlow agent AGENT.md by name.",
    inputSchema: {
      type: "object",
      properties: { agentName: { type: "string" } },
      required: ["agentName"],
      additionalProperties: false
    }
  },
  {
    name: "search_nexaflow_agents",
    description: "Search NexaFlow agents by task keyword.",
    inputSchema: {
      type: "object",
      properties: { query: { type: "string" }, limit: { type: "number" } },
      required: ["query"],
      additionalProperties: false
    }
  },
  {
    name: "run_agent_playbook",
    description: "Generate a structured read-only output from a NexaFlow agent playbook.",
    inputSchema: {
      type: "object",
      properties: {
        agentName: { type: "string" },
        task: { type: "string" },
        context: { type: "object" }
      },
      required: ["agentName", "task"],
      additionalProperties: true
    }
  },
  {
    name: "build_handoff_packet",
    description: "Build a handoff packet between NexaFlow agents.",
    inputSchema: {
      type: "object",
      properties: {
        fromAgent: { type: "string" },
        toAgent: { type: "string" },
        task: { type: "string" },
        context: { type: "object" },
        deliverables: { type: "array", items: { type: "string" } }
      },
      required: ["toAgent", "task"],
      additionalProperties: true
    }
  },
  {
    name: "get_context_contract_schema",
    description: "Return NexaFlow's shared JSON context contracts.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false }
  },
  {
    name: "build_financial_analysis_brief",
    description: "Build a structured financial analysis brief from a user question and optional context.",
    inputSchema: {
      type: "object",
      properties: {
        userQuestion: { type: "string" },
        businessContext: { type: "object" },
        dataContext: { type: "object" },
        evidenceContext: { type: "object" },
        outputDepth: { type: "string", enum: ["quick", "deep"] }
      },
      required: ["userQuestion"],
      additionalProperties: true
    }
  },
  {
    name: "build_report_brief",
    description: "Build a complete or concise report brief for another tool or agent.",
    inputSchema: {
      type: "object",
      properties: {
        reportType: { type: "string", enum: ["complete", "concise"] },
        reportScope: { type: "string", enum: ["fullConversation", "selectedQuestions", "customPeriod"] },
        selectedQuestions: { type: "array", items: { type: "string" } },
        customPeriod: { type: "string" },
        contextSummary: { type: "string" }
      },
      required: ["reportType", "reportScope"],
      additionalProperties: false
    }
  },
  {
    name: "validate_financial_analysis_output",
    description: "Check whether analysis/report text follows NexaFlow evidence and formatting rules.",
    inputSchema: {
      type: "object",
      properties: { text: { type: "string" } },
      required: ["text"],
      additionalProperties: false
    }
  },
  {
    name: "validate_skill_agent_pack",
    description: "Check NexaFlow Skill/Agent files for required fields and examples.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false }
  },
  {
    name: "get_connector_error_help",
    description: "Explain likely cause and next steps for Tableau, Jira, DingTalk, or Confluence error text.",
    inputSchema: {
      type: "object",
      properties: {
        connector: { type: "string" },
        errorText: { type: "string" }
      },
      required: ["errorText"],
      additionalProperties: false
    }
  },
  {
    name: "classify_user_question_for_report",
    description: "Classify whether a user question should be included in a business report.",
    inputSchema: {
      type: "object",
      properties: { question: { type: "string" } },
      required: ["question"],
      additionalProperties: false
    }
  },
  {
    name: "explain_connector_setup",
    description: "Explain required setup fields for Tableau, Jira, DingTalk, or Confluence.",
    inputSchema: {
      type: "object",
      properties: {
        connector: { type: "string", enum: ["tableau", "jira", "dingtalk", "confluence"] }
      },
      required: ["connector"],
      additionalProperties: false
    }
  },
  {
    name: "build_connector_sync_checklist",
    description: "Build a safe pre-sync checklist for a connector without performing sync.",
    inputSchema: {
      type: "object",
      properties: {
        connector: { type: "string", enum: ["tableau", "jira", "dingtalk", "confluence"] },
        businessSpaceName: { type: "string" },
        target: { type: "string" }
      },
      required: ["connector"],
      additionalProperties: false
    }
  }
];

function readText(filePath: string): string {
  return fs.readFileSync(filePath, "utf8");
}

function assertKnownName(kind: "skill" | "agent", name: string): void {
  const known = kind === "skill" ? skillDescriptions : agentDescriptions;
  if (!Object.hasOwn(known, name)) {
    throw new Error(`Unknown ${kind}: ${name}`);
  }
}

function listSkills(): JsonObject[] {
  return Object.entries(skillDescriptions).map(([name, description]) => ({ name, description }));
}

function listAgents(): JsonObject[] {
  return Object.entries(agentDescriptions).map(([name, description]) => ({ name, description }));
}

function searchCollection(kind: "skill" | "agent", query: string, limit = 8): JsonObject[] {
  const q = query.toLowerCase().trim();
  const normalizedQuery = q.replace(/[^a-z0-9]+/g, "");
  const collection = kind === "skill" ? skillDescriptions : agentDescriptions;
  const root = kind === "skill" ? skillsRoot : agentsRoot;
  const fileName = kind === "skill" ? "SKILL.md" : "AGENT.md";
  return Object.entries(collection)
    .map(([name, description]) => {
      const body = readText(path.join(root, name, fileName)).toLowerCase();
      const haystack = `${name}\n${description}\n${body}`;
      const normalizedName = name.replace(/[^a-z0-9]+/g, "");
      const tokenScore = q
        .split(/\s+/)
        .filter(Boolean)
        .reduce((sum, part) => {
          const normalizedPart = part.replace(/[^a-z0-9]+/g, "");
          return sum + (haystack.includes(part) ? 1 : 0) + (normalizedName.includes(normalizedPart) ? 2 : 0);
        }, 0);
      const score = tokenScore + (normalizedName.includes(normalizedQuery) ? 5 : 0);
      return { name, description, score };
    })
    .filter((item) => Number(item.score) > 0 || item.name.includes(q))
    .sort((a, b) => Number(b.score) - Number(a.score) || String(a.name).localeCompare(String(b.name)))
    .slice(0, limit)
    .map(({ name, description, score }) => ({ name, description, score }));
}

function readAgentRegistry(): JsonObject {
  const registryPath = path.join(agentsRoot, "registry.json");
  return JSON.parse(readText(registryPath)) as JsonObject;
}

function runAgentPlaybook(args: JsonObject): string {
  const agentName = String(args.agentName ?? "");
  const task = String(args.task ?? "").trim();
  assertKnownName("agent", agentName);
  const registry = readAgentRegistry();
  const agents = Array.isArray(registry.agents) ? registry.agents : [];
  const entry = agents.find((agent) => (agent as JsonObject).name === agentName) as JsonObject | undefined;
  const skills = Array.isArray(entry?.skills) ? entry.skills.map(String) : [];
  const outputs = Array.isArray(entry?.outputs) ? entry.outputs.map(String) : [];
  return [
    `# ${agentName} Playbook Output`,
    "",
    "## Task",
    task || "- Not provided.",
    "",
    "## Selected Skills",
    skills.length ? skills.map((skill) => `- ${skill}`).join("\n") : "- No registry skills found.",
    "",
    "## Workflow",
    "1. Restate the task and current business-space scope.",
    "2. Use the selected skills to build the requested brief, audit, checklist, or handoff.",
    "3. Separate known facts, assumptions, missing inputs, and safe next steps.",
    "4. Keep the output read-only: do not trigger NexaFlow sync, import, analysis, or report generation.",
    "",
    "## Expected Deliverables",
    outputs.length ? outputs.map((output) => `- ${output}`).join("\n") : "- Structured output matching AGENT.md.",
    "",
    "## Context",
    JSON.stringify(args.context ?? {}, null, 2)
  ].join("\n");
}

function buildHandoffPacket(args: JsonObject): string {
  const fromAgent = args.fromAgent ? String(args.fromAgent) : "user/current agent";
  const toAgent = String(args.toAgent ?? "");
  const task = String(args.task ?? "").trim();
  assertKnownName("agent", toAgent);
  const deliverables = Array.isArray(args.deliverables) ? args.deliverables.map(String) : [];
  return [
    `# NexaFlow Agent Handoff`,
    "",
    `From: ${fromAgent}`,
    `To: ${toAgent}`,
    "",
    "## Task",
    task || "- Not provided.",
    "",
    "## Context",
    JSON.stringify(args.context ?? {}, null, 2),
    "",
    "## Requested Deliverables",
    deliverables.length ? deliverables.map((item) => `- ${item}`).join("\n") : "- Follow the receiving agent AGENT.md output contract.",
    "",
    "## Constraints",
    "- Read-only. Do not trigger live NexaFlow actions.",
    "- Preserve business-space isolation.",
    "- Do not include credentials or secrets.",
    "- State evidence limitations and missing inputs."
  ].join("\n");
}

function validateSkillAgentPack(): JsonObject {
  const issues: JsonObject[] = [];
  for (const name of Object.keys(skillDescriptions)) {
    const filePath = path.join(skillsRoot, name, "SKILL.md");
    if (!fs.existsSync(filePath)) {
      issues.push({ type: "skill", name, severity: "error", message: "Missing SKILL.md" });
      continue;
    }
    const text = readText(filePath);
    const lower = text.toLowerCase();
    if (!/^---\n[\s\S]*?^name:\s*[a-z0-9-]+\s*$/m.test(text)) {
      issues.push({ type: "skill", name, severity: "error", message: "Missing valid name frontmatter." });
    }
    if (!/^description:\s*.+$/m.test(text)) {
      issues.push({ type: "skill", name, severity: "error", message: "Missing description frontmatter." });
    }
    if (!lower.includes("## workflow")) {
      issues.push({ type: "skill", name, severity: "warning", message: "Missing Workflow section." });
    }
    if (!["## output requirements", "## output", "## report usage"].some((marker) => lower.includes(marker))) {
      issues.push({ type: "skill", name, severity: "warning", message: "Missing output requirements." });
    }
    if (!["## boundaries", "## safe sql rules", "## prohibited output"].some((marker) => lower.includes(marker))) {
      issues.push({ type: "skill", name, severity: "warning", message: "Missing boundaries or safety section." });
    }
  }
  const registry = readAgentRegistry();
  const registryNames = new Set((Array.isArray(registry.agents) ? registry.agents : []).map((agent) => String((agent as JsonObject).name)));
  for (const name of Object.keys(agentDescriptions)) {
    if (!registryNames.has(name)) {
      issues.push({ type: "agent", name, severity: "error", message: "Missing from registry.json." });
    }
    const folder = path.join(agentsRoot, name);
    for (const fileName of ["AGENT.md", "input.json", "handoff.md", "acceptance.md"]) {
      if (!fs.existsSync(path.join(folder, fileName))) {
        issues.push({ type: "agent", name, severity: "error", message: `Missing ${fileName}.` });
      }
    }
  }
  return {
    passed: !issues.some((issue) => issue.severity === "error"),
    issueCount: issues.length,
    issues
  };
}

function connectorErrorHelp(args: JsonObject): string {
  const connector = String(args.connector ?? "").toLowerCase();
  const errorText = String(args.errorText ?? "");
  const lower = errorText.toLowerCase();
  const lines = ["# Connector Error Help", "", `Connector: ${connector || "auto"}`, "", "## Likely Cause"];
  if (/missingoperatorid|operatorid/.test(lower)) {
    lines.push("DingTalk requires `operatorId` for this action. Fill the DingTalk user ID of the internal user who performs the document operation.");
    lines.push("", "## Next Steps", "- Add operatorId/userId in the DingTalk connector settings.", "- Confirm the app has document and folder read permissions.", "- Retry sync without pasting Client Secret into chat.");
  } else if (/space id|spaceid|缺少 space/.test(lower)) {
    lines.push("The DingTalk folder link does not expose a Space ID, or the connector cannot infer it.");
    lines.push("", "## Next Steps", "- Paste the full folder link from DingTalk Docs.", "- If available, configure a default Space ID.", "- Confirm the folder belongs to the same organization as the app.");
  } else if (/not a valid api version|api version|3\.22|404001/.test(lower)) {
    lines.push("The Tableau REST API version is not supported by this Tableau server. The client should not hard-code that version.");
    lines.push("", "## Next Steps", "- Use Tableau server REST API version discovery or a supported server version.", "- Re-test PAT login with the negotiated version.", "- Keep View/Crosstab import limits visible in AI read coverage.");
  } else if (/401|unauthorized|invalid token|authentication/.test(lower)) {
    lines.push("Authentication failed. The token, username/email, PAT name, site, or auth type may be wrong.");
    lines.push("", "## Next Steps", "- Verify credentials locally.", "- Confirm connector-specific auth mode.", "- Do not send the token to AI or logs.");
  } else if (/403|forbidden|permission|权限/.test(lower)) {
    lines.push("The user or app lacks permission for the target object.");
    lines.push("", "## Next Steps", "- Confirm project/page/folder/view browse and export/read permissions.", "- Ask the source owner to grant access.", "- Treat missing evidence as a coverage limitation.");
  } else if (/jql|project key|jira/.test(lower)) {
    lines.push("The Jira query or project setting may be invalid or inaccessible.");
    lines.push("", "## Next Steps", "- Check Project Key and JQL syntax.", "- Confirm Browse Project permission.", "- Use a smaller recent-window JQL first.");
  } else {
    lines.push("The error is not recognized by the built-in mapping.");
    lines.push("", "## Next Steps", "- Identify connector type.", "- Check required fields and permissions.", "- Keep table analysis unblocked and record the connector failure as a limitation.");
  }
  lines.push("", "## Safety", "- Do not paste full tokens, Client Secret, cookies, or private headers into prompts.", "- Connector evidence remains scoped to its business space.");
  return lines.join("\n");
}

function buildFinancialAnalysisBrief(args: JsonObject): string {
  const question = String(args.userQuestion ?? "").trim();
  const depth = String(args.outputDepth ?? "deep");
  return [
    "# NexaFlow Financial Analysis Brief",
    "",
    `## User Question`,
    question,
    "",
    `## Mode`,
    depth === "quick"
      ? "Quick answer: use recent conversation, confirmed memory, and cached evidence. Do not collect external data or run SQL."
      : "Deep analysis: prepare selected tables, data coverage, knowledge, memory, project evidence, external evidence, and SQL/Notebook summaries.",
    "",
    "## Required Reasoning",
    "- State what data is available and what is missing.",
    "- Separate facts, inferences, hypotheses, and missing data.",
    "- Keep recommendations operational for fintech product/operations.",
    "- Do not provide investment advice or compliance evasion.",
    "- Format percentages and percentage points to two decimals.",
    "",
    "## Context JSON",
    JSON.stringify(
      {
        businessContext: args.businessContext ?? {},
        dataContext: args.dataContext ?? {},
        evidenceContext: args.evidenceContext ?? {}
      },
      null,
      2
    )
  ].join("\n");
}

function buildReportBrief(args: JsonObject): string {
  const reportType = String(args.reportType);
  const reportScope = String(args.reportScope);
  const selectedQuestions = Array.isArray(args.selectedQuestions) ? args.selectedQuestions.map(String) : [];
  const customPeriod = args.customPeriod ? String(args.customPeriod) : "";
  const contextSummary = args.contextSummary ? String(args.contextSummary) : "";
  const structure =
    reportType === "concise"
      ? ["1. Period data changes", "2. Cause analysis", "3. Action recommendations"]
      : [
          "1. Report type, scope, covered questions, and period policy",
          "2. Executive summary",
          "3. AI read coverage",
          "4. Data coverage and limitations",
          "5. Key metric changes",
          "6. Driver analysis and evidence",
          "7. External/project evidence",
          "8. Facts, inferences, hypotheses, and missing data",
          "9. Opportunities and actions"
        ];
  return [
    "# NexaFlow Report Brief",
    "",
    `Report type: ${reportType}`,
    `Report scope: ${reportScope}`,
    customPeriod ? `Custom period: ${customPeriod}` : "Custom period: not specified",
    "",
    "## Selected Questions",
    selectedQuestions.length ? selectedQuestions.map((q, index) => `${index + 1}. ${q}`).join("\n") : "- Use all valid business questions in the current conversation.",
    "",
    "## Context Summary",
    contextSummary || "- Not provided.",
    "",
    "## Required Structure",
    structure.map((line) => `- ${line}`).join("\n"),
    "",
    "## Rules",
    "- Do not include UI/tool/debug questions unless explicitly selected.",
    "- If no period is specified, write full-period overview and do not force latest-vs-previous comparison.",
    "- Use correction memory over old AI conclusions.",
    "- Format percentages and percentage points to two decimals."
  ].join("\n");
}

function validateFinancialOutput(text: string): JsonObject {
  const issues: JsonObject[] = [];
  const checks = [
    { key: "facts", pattern: /(事实|fact)/i, message: "Missing explicit facts section or label." },
    { key: "inferences", pattern: /(推断|inference)/i, message: "Missing explicit inference section or label." },
    { key: "hypotheses", pattern: /(假设|hypothesis)/i, message: "Missing explicit hypothesis section or label." },
    { key: "missingData", pattern: /(需补数据|缺少|missing data|data gap)/i, message: "Missing missing-data or limitation statement." },
    { key: "readCoverage", pattern: /(AI 读取|读取到的数据|read coverage|data read)/i, message: "Missing AI read coverage." }
  ];
  for (const check of checks) {
    if (!check.pattern.test(text)) {
      issues.push({ code: check.key, severity: "warning", message: check.message });
    }
  }
  const badPercent = text.match(/[-+]?\d+(?:\.\d{1}|\.\d{3,})\s*%/g) ?? [];
  const badPoints = text.match(/[-+]?\d+(?:\.\d{1}|\.\d{3,})\s*个?百分点/g) ?? [];
  for (const value of [...badPercent, ...badPoints]) {
    issues.push({
      code: "percentage_format",
      severity: "warning",
      message: `Percentage-like value should use exactly two decimals: ${value}`
    });
  }
  return {
    passed: issues.length === 0,
    issueCount: issues.length,
    issues
  };
}

function classifyQuestion(question: string): JsonObject {
  const q = question.toLowerCase();
  const toolPattern = /(按钮|界面|卡顿|崩溃|启动|打包|dmg|gui|hover|窗口|sidebar|mcp|skill|agent|token|怎么填写|what is|where is)/i;
  const businessPattern = /(指标|转化|漏斗|获客|注册|kyc|审核|授信|交易|留存|复购|还款|逾期|风控|渠道|活动|收入|成本|竞品|外部事件|数据变化|原因|report|kpi|metric)/i;
  if (toolPattern.test(q) && !businessPattern.test(q)) {
    return { decision: "exclude", reason: "Tool, UI, setup, or technical-operation question." };
  }
  if (businessPattern.test(q)) {
    return { decision: "include", reason: "Business analysis question relevant to report scope." };
  }
  return { decision: "auto", reason: "Question is ambiguous; include only if the surrounding conversation makes it a business question." };
}

function connectorSetup(connector: string): string {
  const requirements = connectorRequirements[connector];
  if (!requirements) throw new Error(`Unknown connector: ${connector}`);
  const boundary =
    connector === "tableau"
      ? "Tableau view exports are not guaranteed to equal the full underlying data source."
      : connector === "jira"
        ? "Jira is project status evidence; issue status is not proof of release."
        : connector === "dingtalk"
          ? "DingTalk documents are document evidence; update time is not actual launch time."
          : "Confluence pages are knowledge/project evidence; page time is not actual launch time.";
  return [
    `# ${connector} setup`,
    "",
    "## Required fields",
    requirements.map((item) => `- ${item}`).join("\n"),
    "",
    "## Safety",
    "- Store credentials locally only.",
    "- Do not send tokens to AI prompts, logs, reports, or exports.",
    "- Bind the connector to a business space.",
    "",
    "## Evidence boundary",
    boundary
  ].join("\n");
}

function connectorChecklist(args: JsonObject): string {
  const connector = String(args.connector);
  const businessSpaceName = args.businessSpaceName ? String(args.businessSpaceName) : "current business space";
  const target = args.target ? String(args.target) : "configured target";
  return [
    `# ${connector} sync checklist`,
    "",
    `Business space: ${businessSpaceName}`,
    `Target: ${target}`,
    "",
    "1. Confirm the connector is bound to the correct business space.",
    "2. Confirm required credentials are present locally and not copied into prompts.",
    "3. Confirm read permissions for the target object.",
    "4. Confirm source time semantics: created, updated, published, collected, event, or status-change time.",
    "5. Confirm sync limits and filters.",
    "6. After sync, label the result as report data, project evidence, document evidence, or external evidence.",
    "7. If sync fails, keep table analysis unblocked and record the failure as a limitation."
  ].join("\n");
}

function toolResult(text: string | JsonValue): JsonObject {
  return {
    content: [
      {
        type: "text",
        text: typeof text === "string" ? text : JSON.stringify(text, null, 2)
      }
    ]
  };
}

function callTool(name: string, args: JsonObject = {}): JsonObject {
  switch (name) {
    case "list_nexaflow_skills":
      return toolResult(listSkills());
    case "get_nexaflow_skill": {
      const skillName = String(args.skillName ?? "");
      assertKnownName("skill", skillName);
      return toolResult(readText(path.join(skillsRoot, skillName, "SKILL.md")));
    }
    case "search_nexaflow_skills":
      return toolResult(searchCollection("skill", String(args.query ?? ""), Number(args.limit ?? 8)));
    case "list_nexaflow_agents":
      return toolResult(listAgents());
    case "get_nexaflow_agent": {
      const agentName = String(args.agentName ?? "");
      assertKnownName("agent", agentName);
      return toolResult(readText(path.join(agentsRoot, agentName, "AGENT.md")));
    }
    case "search_nexaflow_agents":
      return toolResult(searchCollection("agent", String(args.query ?? ""), Number(args.limit ?? 8)));
    case "run_agent_playbook":
      return toolResult(runAgentPlaybook(args));
    case "build_handoff_packet":
      return toolResult(buildHandoffPacket(args));
    case "get_context_contract_schema":
      return toolResult(JSON.parse(readText(path.join(sharedRoot, "context-contracts.json"))) as JsonValue);
    case "build_financial_analysis_brief":
      return toolResult(buildFinancialAnalysisBrief(args));
    case "build_report_brief":
      return toolResult(buildReportBrief(args));
    case "validate_financial_analysis_output":
      return toolResult(validateFinancialOutput(String(args.text ?? "")));
    case "validate_skill_agent_pack":
      return toolResult(validateSkillAgentPack());
    case "get_connector_error_help":
      return toolResult(connectorErrorHelp(args));
    case "classify_user_question_for_report":
      return toolResult(classifyQuestion(String(args.question ?? "")));
    case "explain_connector_setup":
      return toolResult(connectorSetup(String(args.connector ?? "")));
    case "build_connector_sync_checklist":
      return toolResult(connectorChecklist(args));
    default:
      throw new Error(`Unknown tool: ${name}`);
  }
}

function resources(): JsonObject[] {
  const skillResources = Object.keys(skillDescriptions).map((name) => ({
    uri: `nexaflow://skills/${name}`,
    name: `Skill: ${name}`,
    mimeType: "text/markdown"
  }));
  const agentResources = Object.keys(agentDescriptions).map((name) => ({
    uri: `nexaflow://agents/${name}`,
    name: `Agent: ${name}`,
    mimeType: "text/markdown"
  }));
  const templateResources = Object.keys(templateFiles).map((name) => ({
    uri: `nexaflow://templates/${name}`,
    name: `Template: ${name}`,
    mimeType: "text/markdown"
  }));
  const checklistResources = Object.keys(checklistFiles).map((name) => ({
    uri: `nexaflow://checklists/${name}`,
    name: `Checklist: ${name}`,
    mimeType: "text/markdown"
  }));
  return [
    ...skillResources,
    ...agentResources,
    ...templateResources,
    ...checklistResources,
    {
      uri: "nexaflow://schemas/context-contracts",
      name: "Context Contracts",
      mimeType: "application/json"
    },
    {
      uri: "nexaflow://policies/financial-prompt-policy",
      name: "Financial Output Policy",
      mimeType: "text/markdown"
    },
    {
      uri: "nexaflow://examples/report-brief",
      name: "Report Brief Example",
      mimeType: "text/markdown"
    },
    {
      uri: "nexaflow://agents/registry",
      name: "Agent Registry",
      mimeType: "application/json"
    }
  ];
}

function readResource(uri: string): JsonObject {
  let text: string;
  let mimeType = "text/markdown";
  if (uri.startsWith("nexaflow://skills/")) {
    const name = uri.slice("nexaflow://skills/".length);
    assertKnownName("skill", name);
    text = readText(path.join(skillsRoot, name, "SKILL.md"));
  } else if (uri.startsWith("nexaflow://agents/")) {
    const name = uri.slice("nexaflow://agents/".length);
    if (name === "registry") {
      mimeType = "application/json";
      text = readText(path.join(agentsRoot, "registry.json"));
    } else {
      assertKnownName("agent", name);
      text = readText(path.join(agentsRoot, name, "AGENT.md"));
    }
  } else if (uri.startsWith("nexaflow://templates/")) {
    const name = uri.slice("nexaflow://templates/".length);
    const filePath = templateFiles[name];
    if (!filePath) throw new Error(`Unknown template: ${name}`);
    text = readText(filePath);
  } else if (uri.startsWith("nexaflow://checklists/")) {
    const name = uri.slice("nexaflow://checklists/".length);
    const filePath = checklistFiles[name];
    if (!filePath) throw new Error(`Unknown checklist: ${name}`);
    text = readText(filePath);
  } else if (uri === "nexaflow://schemas/context-contracts") {
    mimeType = "application/json";
    text = readText(path.join(sharedRoot, "context-contracts.json"));
  } else if (uri === "nexaflow://policies/financial-prompt-policy") {
    text = readText(path.join(sharedRoot, "financial-output-policy.md"));
  } else if (uri === "nexaflow://examples/report-brief") {
    text = readText(path.join(sharedRoot, "report-brief-example.md"));
  } else {
    throw new Error(`Unknown resource: ${uri}`);
  }
  return { contents: [{ uri, mimeType, text }] };
}

function ok(id: JsonValue, result: JsonObject): void {
  process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id, result }) + "\n");
}

function fail(id: JsonValue, error: unknown): void {
  process.stdout.write(
    JSON.stringify({
      jsonrpc: "2.0",
      id,
      error: {
        code: -32000,
        message: error instanceof Error ? error.message : String(error)
      }
    }) + "\n"
  );
}

function handle(request: JsonObject): void {
  const id = request.id ?? null;
  const method = String(request.method ?? "");
  const params = (request.params ?? {}) as JsonObject;
  try {
    if (!Object.hasOwn(request, "id")) {
      return;
    }
    switch (method) {
      case "initialize":
        ok(id, {
          protocolVersion: "2024-11-05",
          capabilities: { tools: {}, resources: {} },
          serverInfo: { name: "nexaflow-mcp", version: "0.1.0" }
        });
        break;
      case "tools/list":
        ok(id, { tools });
        break;
      case "tools/call":
        ok(id, callTool(String(params.name ?? ""), (params.arguments ?? {}) as JsonObject));
        break;
      case "resources/list":
        ok(id, { resources: resources() });
        break;
      case "resources/read":
        ok(id, readResource(String(params.uri ?? "")));
        break;
      default:
        throw new Error(`Unsupported method: ${method}`);
    }
  } catch (error) {
    fail(id, error);
  }
}

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
rl.on("line", (line) => {
  if (!line.trim()) return;
  try {
    handle(JSON.parse(line) as JsonObject);
  } catch (error) {
    fail(null, error);
  }
});
