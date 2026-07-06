#NexaFlow

[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue.svg)](https://developer.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

> 面向海外金融产品与运营团队的本地优先 AI 数据分析工作台。导入表格即可用自然语言提问，系统自动生成 SQL 证据、检索外部资料。

---

## 简介

NexaFlow是一款运行在 macOS 上的原生 Swift 应用。它将业务数据（CSV / Excel / Tableau 导出）组织到按国家/业务线/时区划分的 **业务空间** 中，通过本地 DuckDB 进行分析，并借助大语言模型实现自然语言问答、机会挖掘与报告生成。

核心设计理念：

- **本地优先**：原始数据、分析中间表、证据 SQL 均落在本地 DuckDB，不依赖云端数据仓库。
- **可验证**：每条 AI 结论都附带“AI 读取到的数据”覆盖块与可执行的 DuckDB SQL/Notebook 证据。
- **可记忆**：用户的纠正、采纳、字段释义会沉淀为长期记忆，提升后续会话的准确性与一致性。
- **可恢复**：AI 任务进入持久化队列，App 重启后仍可继续执行、重试或取消。

---

## 功能特性

### 数据接入
- 导入 CSV、XLSX、XLS 文件
- 支持 Tableau Crosstab / 视图导出（`.hyper`/`.tdsx` 直连读取已纳入 Roadmap）
- 自动识别表头、周期列、指标语义与数据风险

### 自然语言分析
- 三种上下文模式：仅表格 / 表格 + 知识库 / 全部资料
- 基于 DuckDB 的 SQL/Notebook 证据生成
- Tavily 外部资料检索与 Confluence/本地文件夹知识库引用
- 多轮会话、快速跟进、深度再分析、完整汇报生成

### AI 任务与报告
- 持久化后台 AI 任务队列，支持自动重试、指数退避、App 重启恢复
- 一键生成“老板版”Word 汇报
- AI 机会评分与业务地图
- 数据源推荐与外部事件影响分析

### 记忆与调优
- 纠正记忆：用户纠正后的答案会反馈到后续会话
- 字段/指标语义词典
- 分析模板与业务空间级配置

---

## 系统要求

- macOS 13.0 Ventura 或更高版本
- Apple Silicon 或 Intel Mac
- Xcode 15+（开发构建）
- Swift 5.9+

---

## 快速开始

### 1. 克隆仓库

```bash
git clone <repository-url>
cd IterationPilot
```

### 2. 命令行构建

```bash
swift build --disable-sandbox
```

### 3. 运行 App

```bash
swift run IterationPilot
```

或者使用辅助脚本：

```bash
./script/build_and_run.sh
```

### 4. 首次使用

1. 在设置中填写 LLM API Key（支持自定义 Base URL 与模型名称）
2. 创建一个业务空间并设置国家、时区、语义偏好
3. 导入数据文件，生成 DataPack
4. 创建分析任务，选择要使用的报表
5. 在分析会话中输入你的第一个问题

---

## 项目结构

```
IterationPilot/
├── Package.swift                         # Swift Package Manager 配置
├── Sources/
│   ├── CLibXLS/                          # XLS 读取 C 库封装
│   ├── IterationPilot/
│   │   ├── App/                          # App 入口与生命周期
│   │   ├── Models/                       # 数据模型（业务空间、DataPack、会话、任务等）
│   │   ├── Services/                     # 核心业务服务（AI、分析引擎、导入、队列等）
│   │   ├── Views/                        # SwiftUI 视图
│   │   └── ...
│   └── IterationPilot/App/               # 可执行目标入口
├── Tests/
│   └── IterationPilotTests/              # 回归测试与单元测试
└── script/                               # 构建、运行、回归测试脚本
```

### 主要模块

| 模块 | 说明 |
|------|------|
| `IterationPilotCore` | 核心库：模型、服务、分析引擎、AI 任务队列 |
| `IterationPilot` | macOS App 可执行目标 |
| `IterationPilotRegressionTests` | 非 GUI 回归测试入口 |

---

## 依赖

本项目使用 Swift Package Manager 管理依赖：

- [CoreXLSX](https://github.com/CoreOffice/CoreXLSX) — XLSX 解析
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) — ZIP 解包
- [DuckDB Swift](https://github.com/duckdb/duckdb-swift) — 本地分析数据库
- `CLibXLS` — 自包含的 XLS 读取库
- 系统 `sqlite3`

---

## 配置说明

### LLM API

在 App 设置中配置：

- API Key
- Base URL（兼容 OpenAI 格式）
- 模型名称

也支持通过环境变量或项目级配置注入。

### Confluence 知识库

配置 Confluence Base URL、Bearer Token 与 Root Page ID，即可在分析时引用 Confluence 页面内容。

Token 优先级：

1. App 设置中显式填写的 Bearer Token
2. 环境变量 `CONFLUENCE_TOKEN`

### Tavily 外部检索

配置 Tavily API Key 后，全资料模式会自动检索与问题相关的外部网页证据。

---

## 开发与测试

### 非 GUI 回归测试

```bash
./script/non_gui_regression.sh
```

### 构建并验证

```bash
./script/build_and_run.sh --verify
```

### GUI 回归与 DMG 打包

GUI 回归和 DMG 打包需要用户明确授权，默认不会自动执行。

---

## Roadmap

- [x] 持久化 AI 任务队列（重试、恢复、日志）
- [x] 输入框系统快捷键与占位提示修复
- [ ] Tableau 底层数据源直连读取（`.hyper`/`.tdsx`）
- [ ] 钉钉文档连接器
- [ ] Jira 证据集成深化
- [ ] 更细粒度的任务并发控制与队列筛选
- [ ] AI 任务中心全局视图
- [ ] 导出预览与多模板 Word/PDF 导出

详细待办见 [`PROJECT_TODOS.md`](PROJECT_TODOS.md)。

---

## 贡献

欢迎提交 Issue 与 PR。在提交前请确保：

1. 代码通过 `swift build --disable-sandbox`
2. 非 GUI 回归测试通过 `./script/non_gui_regression.sh`
3. 新增功能附带对应测试或文档更新

---

## 许可证

本项目采用 [MIT License](LICENSE)。

---

## 联系我们

如有问题或合作意向，欢迎通过 GitHub Issue 与我们联系。
