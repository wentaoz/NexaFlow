# NexaFlow Skill / Agent / MCP 傻瓜式使用说明

这份说明给不关心技术细节的人看。你只需要知道：这套东西不是 NexaFlow App 本体功能，而是把 NexaFlow 的分析方法、汇报规则、连接器解释、证据审查能力，打包给其他 AI 工具复用。

## 1. 这三类东西分别是什么

| 名称 | 可以理解成 | 主要用途 | 会不会改 App 数据 |
|---|---|---|---|
| Skill | 一套专业做事说明书 | 告诉 AI 遇到某类问题该怎么分析、怎么输出 | 不会 |
| Agent | 一个分工角色 | 让 AI 按“数据接入、分析准备、汇报、证据审查”等角色办事 | 不会 |
| MCP | 给其他工具调用的接口 | 让 Codex、Claude Desktop 等工具可以读取这些 Skill/Agent，并生成分析 brief、汇报 brief、校验输出 | 不会 |

一句话：
**Skill/Agent 是方法论，MCP 是把这些方法论开放给其他工具调用的接口。**

## 2. 当前能做什么，不能做什么

### 当前能做

- 查看 NexaFlow 的分析 Skill。
- 查看 NexaFlow 的 Agent 工作流。
- 生成金融产品/运营分析任务说明。
- 生成完整汇报或简洁汇报的任务说明。
- 检查一段分析输出是否符合 NexaFlow 要求。
- 判断某个用户问题是否应该进入汇报范围。
- 解释 Tableau / Jira / 钉钉 / Confluence 需要填写什么。
- 生成连接器同步前检查清单。
- 搜索合适的 Skill / Agent。
- 根据 Agent 工作流生成交接包。
- 根据常见错误解释 Tableau、Jira、钉钉、Confluence 失败原因。
- 校验整个 Skill/Agent 包是否缺说明、缺边界或缺示例。

### 当前不能做

- 不能直接启动 NexaFlow App。
- 不能直接导入表格。
- 不能直接同步 Jira、钉钉、Tableau、Confluence。
- 不能直接触发 App 里的 AI 分析。
- 不能直接生成 App 里的完整汇报或简洁汇报。
- 不能读取或上传你的 token。

这是第一版的安全边界：**只读、无副作用**。

## 3. 文件在哪里

| 内容 | 路径 |
|---|---|
| Skill 目录 | `/Users/WilliamChang/Documents/Playground/IterationPilot/skills/nexaflow` |
| Agent 目录 | `/Users/WilliamChang/Documents/Playground/IterationPilot/agents/nexaflow` |
| MCP 目录 | `/Users/WilliamChang/Documents/Playground/IterationPilot/mcp/nexaflow-mcp` |
| 总说明 | `/Users/WilliamChang/Documents/Playground/IterationPilot/docs/nexaflow-skill-agent-mcp-pack.md` |
| 本说明 | `/Users/WilliamChang/Documents/Playground/IterationPilot/docs/nexaflow-skill-agent-mcp-usage-guide.md` |

## 4. 最简单的使用方式

### 方式 A：直接让 Codex 按某个 Skill 做事

你可以这样对 Codex 说：

```text
请按这个 Skill 的规则帮我分析：
/Users/WilliamChang/Documents/Playground/IterationPilot/skills/nexaflow/financial-product-analysis/SKILL.md

问题：为什么本周注册上升了，但是交易金额没有跟上？
```

或者：

```text
请按这个 Skill 的规则生成一份简洁汇报：
/Users/WilliamChang/Documents/Playground/IterationPilot/skills/nexaflow/kpi-reporting/SKILL.md

汇报内容只要：周期内数据变化、原因分析、动作建议。
```

### 方式 B：让 Codex 扮演某个 Agent

你可以这样说：

```text
请按这个 Agent 的职责工作：
/Users/WilliamChang/Documents/Playground/IterationPilot/agents/nexaflow/evidence-audit-agent/AGENT.md

帮我检查下面这段分析有没有证据不足、把推断当事实、或者遗漏需补数据。
```

常用 Agent：

| 你想做什么 | 推荐 Agent |
|---|---|
| 不知道该用哪个角色 | `orchestrator-agent` |
| 检查数据源/连接器怎么填 | `data-acquisition-agent` |
| 准备分析上下文 | `analysis-prep-agent` |
| 做金融产品运营分析 | `financial-analysis-agent` |
| 生成汇报 | `report-agent` |
| 判断哪些问题进入汇报 | `report-scope-agent` |
| 检查 AI 结论靠不靠谱 | `evidence-audit-agent` |
| 处理纠偏记忆 | `memory-curator-agent` |
| 解释同步失败 | `connector-sync-agent` |
| 排查连接器错误 | `connector-debug-agent` |
| 判断 Tableau 导入边界 | `tableau-import-advisor-agent` |
| 审查输出质量 | `quality-guard-agent` |

## 5. MCP 怎么用

MCP 是给支持 MCP 的工具使用的，比如 Claude Desktop、部分 Codex 环境、其他本地 AI 工具。

### 5.1 先确认能启动

在终端运行：

```bash
cd /Users/WilliamChang/Documents/Playground/IterationPilot/mcp/nexaflow-mcp
npm run start
```

如果没有报错，就说明 MCP server 能启动。

退出时按：

```text
Control + C
```

### 5.2 接到 Claude Desktop

打开 Claude Desktop 的 MCP 配置文件，把下面配置加进去：

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

重启 Claude Desktop 后，你就可以问：

```text
用 nexaflow 的工具列出可用 skills。
```

或者：

```text
用 nexaflow 生成一份金融产品分析 brief：
问题是“为什么本周注册增长但交易没有增长？”
```

### 5.3 接到其他 MCP 工具

只要那个工具支持 stdio MCP，就填这个命令：

```bash
node --experimental-strip-types /Users/WilliamChang/Documents/Playground/IterationPilot/mcp/nexaflow-mcp/src/server.ts
```

## 6. MCP 里有哪些工具

| 工具名 | 作用 | 适合什么时候用 |
|---|---|---|
| `list_nexaflow_skills` | 列出所有 Skill | 不知道有哪些能力时 |
| `get_nexaflow_skill` | 读取某个 Skill 说明 | 想让其他 AI 按 NexaFlow 规则做事时 |
| `search_nexaflow_skills` | 按关键词搜索 Skill | 想找 Tableau、汇报、纠偏等能力时 |
| `list_nexaflow_agents` | 列出所有 Agent | 不知道该让哪个角色处理时 |
| `get_nexaflow_agent` | 读取某个 Agent 工作流 | 想让其他 AI 扮演某个角色时 |
| `search_nexaflow_agents` | 按任务搜索 Agent | 想自动找到合适角色时 |
| `run_agent_playbook` | 按某个 Agent 生成结构化输出 | 想让外部工具按 NexaFlow 角色办事时 |
| `build_handoff_packet` | 生成 Agent 之间交接包 | 多 Agent 协作时 |
| `get_context_contract_schema` | 获取上下文 JSON 契约 | 要把数据结构化交给其他工具时 |
| `build_financial_analysis_brief` | 生成分析任务说明 | 要让其他 AI 做产品运营分析时 |
| `build_report_brief` | 生成汇报任务说明 | 要让其他 AI 生成完整/简洁汇报时 |
| `validate_financial_analysis_output` | 检查分析输出质量 | 担心 AI 瞎推、证据不足、百分比格式不对时 |
| `validate_skill_agent_pack` | 校验 Skill/Agent 包 | 修改能力包后检查是否缺字段 |
| `get_connector_error_help` | 解释连接器错误 | 粘贴错误文本后获得排查建议 |
| `classify_user_question_for_report` | 判断问题是否进入汇报 | 多轮对话后筛报告范围时 |
| `explain_connector_setup` | 解释连接器怎么填 | Tableau/Jira/钉钉/Confluence 配置前 |
| `build_connector_sync_checklist` | 生成同步前检查清单 | 准备接入或排查同步失败时 |

## 7. 常用场景示例

### 场景 1：让其他 AI 帮你分析指标异常

你可以说：

```text
请调用 NexaFlow MCP 的 build_financial_analysis_brief。

userQuestion:
为什么本周注册增长 12.00%，但交易金额下降 5.80%？

outputDepth:
deep
```

得到 brief 后，把它交给另一个 AI：

```text
请严格按这个 NexaFlow brief 输出分析，区分事实、推断、假设、需补数据。
```

### 场景 2：生成完整汇报范围说明

```text
请调用 NexaFlow MCP 的 build_report_brief。

reportType:
complete

reportScope:
selectedQuestions

selectedQuestions:
1. 本周交易金额为什么下降？
2. 获客渠道是否影响了 KYC 通过率？
```

### 场景 3：检查一段 AI 输出是否靠谱

```text
请调用 NexaFlow MCP 的 validate_financial_analysis_output。

text:
这里粘贴 AI 输出。
```

它会检查：

- 有没有说明 AI 读到了什么。
- 有没有区分事实、推断、假设、需补数据。
- 百分比是不是两位小数。
- 有没有明显缺证据。

### 场景 4：问 Jira / Tableau / 钉钉要填什么

```text
请调用 NexaFlow MCP 的 explain_connector_setup。

connector:
dingtalk
```

它会告诉你需要：

- Client ID
- Client Secret
- AgentId
- operatorId
- 文件夹链接或 folder ID + Space ID
- 文档/表格读取权限

### 场景 5：排查连接器错误

```text
请调用 NexaFlow MCP 的 get_connector_error_help。

connector:
tableau

errorText:
版本 “3.22” 不是有效的 API 版本。
```

它会告诉你：

- 可能是 Tableau REST API 版本被硬编码。
- 应该做版本协商或改用服务器支持的版本。
- 视图导入仍要标注 View Export 限制。

### 场景 6：搜索合适的 Agent

```text
请调用 NexaFlow MCP 的 search_nexaflow_agents。

query:
钉钉 同步失败 operatorId
```

常见会返回：

- `connector-debug-agent`
- `connector-sync-agent`
- `data-acquisition-agent`

## 8. 什么时候用 Skill，什么时候用 Agent，什么时候用 MCP

| 情况 | 用什么 |
|---|---|
| 你在 Codex 当前会话里直接做事 | Skill |
| 你想让 AI 按一个角色处理问题 | Agent |
| 你想让 Claude Desktop、其他工具也能调用 NexaFlow 规则 | MCP |
| 你只是想看规则文本 | Skill 或 Agent |
| 你想生成结构化 brief 给别的 AI | MCP |
| 你想直接操作 NexaFlow App | 当前第一版 MCP 不支持 |

## 9. 常见问题

### Q1：这会不会影响 NexaFlow App？

不会。第一版只新增文档和只读 MCP server，不改 App 的分析、汇报、数据源、知识库逻辑。

### Q2：为什么 MCP 不能直接帮我同步钉钉或 Jira？

因为第一版是安全只读版本。同步、导入、生成汇报都属于有副作用操作，后续要单独设计权限、确认弹窗、审计日志和取消机制。

### Q3：这些 Skill 会自动出现在 Codex Skill 列表里吗？

不会自动出现。它们现在是项目内版本化文件。你可以通过绝对路径让 Codex 使用它们。

如果你想安装到 Codex 的 Skill 目录，可以运行：

```bash
cd /Users/WilliamChang/Documents/Playground/IterationPilot
./script/install_nexaflow_skills.sh
./script/install_nexaflow_skills.sh --apply
```

第一行是 dry-run，只预览；第二行才会复制。

### Q4：MCP 会读取我的 token 吗？

不会。当前 MCP 工具只解释需要什么字段，不读取、不保存、不上传 token。

### Q5：我应该从哪个文件开始看？

先看：

```text
/Users/WilliamChang/Documents/Playground/IterationPilot/docs/nexaflow-skill-agent-mcp-pack.md
```

如果只是想知道怎么用，就看本文档。

## 10. 推荐使用顺序

第一次使用建议按这个顺序：

1. 看本文档。
2. 运行 `npm run start` 确认 MCP 能启动。
3. 在 MCP 工具里调用 `list_nexaflow_skills`。
4. 调用 `get_nexaflow_skill` 看某个 Skill。
5. 调用 `search_nexaflow_agents` 找一个合适角色。
6. 调用 `build_financial_analysis_brief` 生成一个分析 brief。
7. 调用 `validate_financial_analysis_output` 检查一段 AI 分析。
8. 修改 Skill/Agent 后运行 `./script/quick_validate.py`。

## 11. 后续可以升级什么

后续如果你确认要开放写入型能力，可以做第二版 MCP：

- 触发 Jira / 钉钉 / Tableau / Confluence 同步。
- 导入 Tableau View。
- 创建分析任务。
- 触发深度分析。
- 生成完整汇报。
- 生成简洁汇报。

但这些都需要明确权限、确认机制和日志，不建议直接混进第一版。
