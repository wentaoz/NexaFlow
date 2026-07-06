# NexaFlow MCP

Read-only stdio MCP server for NexaFlow reusable skills, agents, and analysis contracts.

## Start

```bash
cd mcp/nexaflow-mcp
npm run start
```

The server has no npm dependencies. It uses Node's built-in TypeScript type stripping, so Node 22+ is required.

## Codex / Claude Desktop command

```json
{
  "command": "node",
  "args": [
    "--experimental-strip-types",
    "/absolute/path/to/IterationPilot/mcp/nexaflow-mcp/src/server.ts"
  ]
}
```

## Safety

- Tools are read-only and deterministic.
- Tools do not call NexaFlow App actions.
- Tools do not sync connectors, import data, trigger analysis, generate reports, or read tokens.
- Connector setup tools explain requirements only.
