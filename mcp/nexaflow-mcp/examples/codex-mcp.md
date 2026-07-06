# Codex MCP Configuration Example

Add a stdio MCP server entry that points to the local NexaFlow MCP server:

```json
{
  "mcpServers": {
    "nexaflow": {
      "command": "node",
      "args": [
        "--experimental-strip-types",
        "/Users/WilliamChang/Documents/Playground/IterationPilot/mcp/nexaflow-mcp/src/server.ts"
      ]
    }
  }
}
```

## Quick Checks

1. Start a client that supports MCP stdio.
2. Call `list_nexaflow_skills`.
3. Call `search_nexaflow_agents` with `Tableau`.
4. Call `get_connector_error_help` with a real connector error.

The v1 server is read-only. It does not trigger NexaFlow App sync, import, analysis, or report generation.
