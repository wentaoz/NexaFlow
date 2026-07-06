import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

type RpcResponse = {
  id: number;
  result?: any;
  error?: { code: number; message: string };
};

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const serverPath = path.resolve(__dirname, "../src/server.ts");

const child = spawn(process.execPath, ["--experimental-strip-types", serverPath], {
  stdio: ["pipe", "pipe", "pipe"]
});

const responses = new Map<number, RpcResponse>();
let stdoutBuffer = "";
let stderr = "";

child.stdout.setEncoding("utf8");
child.stderr.setEncoding("utf8");
child.stdout.on("data", (chunk) => {
  stdoutBuffer += chunk;
  let index = stdoutBuffer.indexOf("\n");
  while (index >= 0) {
    const line = stdoutBuffer.slice(0, index).trim();
    stdoutBuffer = stdoutBuffer.slice(index + 1);
    if (line) {
      const parsed = JSON.parse(line) as RpcResponse;
      responses.set(parsed.id, parsed);
    }
    index = stdoutBuffer.indexOf("\n");
  }
});
child.stderr.on("data", (chunk) => {
  stderr += chunk;
});

let nextId = 1;
function request(method: string, params: any = {}): Promise<RpcResponse> {
  const id = nextId++;
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
  return new Promise((resolve, reject) => {
    const started = Date.now();
    const timer = setInterval(() => {
      const response = responses.get(id);
      if (response) {
        clearInterval(timer);
        resolve(response);
      } else if (Date.now() - started > 5000) {
        clearInterval(timer);
        reject(new Error(`Timed out waiting for ${method}. stderr=${stderr}`));
      }
    }, 20);
  });
}

try {
  const init = await request("initialize", {
    protocolVersion: "2024-11-05",
    capabilities: {},
    clientInfo: { name: "protocol-test", version: "0.0.1" }
  });
  assert.equal(init.error, undefined);
  assert.equal(init.result.serverInfo.name, "nexaflow-mcp");

  const tools = await request("tools/list");
  assert.equal(tools.error, undefined);
  assert.ok(tools.result.tools.some((tool: any) => tool.name === "list_nexaflow_skills"));
  assert.ok(tools.result.tools.some((tool: any) => tool.name === "search_nexaflow_skills"));
  assert.ok(tools.result.tools.some((tool: any) => tool.name === "run_agent_playbook"));
  assert.ok(tools.result.tools.some((tool: any) => tool.name === "validate_financial_analysis_output"));
  assert.ok(tools.result.tools.some((tool: any) => tool.name === "get_connector_error_help"));

  const skillList = await request("tools/call", {
    name: "list_nexaflow_skills",
    arguments: {}
  });
  assert.equal(skillList.error, undefined);
  assert.match(skillList.result.content[0].text, /financial-product-analysis/);

  const validation = await request("tools/call", {
    name: "validate_financial_analysis_output",
    arguments: { text: "结论：注册增长 8.7%。" }
  });
  assert.equal(validation.error, undefined);
  assert.match(validation.result.content[0].text, /percentage_format/);

  const skillSearch = await request("tools/call", {
    name: "search_nexaflow_skills",
    arguments: { query: "Tableau connector", limit: 5 }
  });
  assert.equal(skillSearch.error, undefined);
  assert.match(skillSearch.result.content[0].text, /connector-troubleshooting|data-ingestion-semantics/);

  const agentSearch = await request("tools/call", {
    name: "search_nexaflow_agents",
    arguments: { query: "report scope", limit: 5 }
  });
  assert.equal(agentSearch.error, undefined);
  assert.match(agentSearch.result.content[0].text, /report-scope-agent/);

  const connectorHelp = await request("tools/call", {
    name: "get_connector_error_help",
    arguments: { connector: "dingtalk", errorText: "MissingoperatorId is mandatory for this action." }
  });
  assert.equal(connectorHelp.error, undefined);
  assert.match(connectorHelp.result.content[0].text, /operatorId/);

  const packValidation = await request("tools/call", {
    name: "validate_skill_agent_pack",
    arguments: {}
  });
  assert.equal(packValidation.error, undefined);
  assert.match(packValidation.result.content[0].text, /passed/);

  const resources = await request("resources/list");
  assert.equal(resources.error, undefined);
  assert.ok(resources.result.resources.some((resource: any) => resource.uri === "nexaflow://schemas/context-contracts"));
  assert.ok(resources.result.resources.some((resource: any) => resource.uri === "nexaflow://agents/registry"));
  assert.ok(resources.result.resources.some((resource: any) => resource.uri === "nexaflow://templates/analysis-brief-template"));

  const schema = await request("resources/read", {
    uri: "nexaflow://schemas/context-contracts"
  });
  assert.equal(schema.error, undefined);
  assert.match(schema.result.contents[0].text, /BusinessContext/);

  const registry = await request("resources/read", {
    uri: "nexaflow://agents/registry"
  });
  assert.equal(registry.error, undefined);
  assert.match(registry.result.contents[0].text, /orchestrator-agent/);
} finally {
  child.kill();
}
