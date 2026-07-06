---
name: data-ingestion-semantics
description: Explain and plan NexaFlow data ingestion semantics for local files, Tableau views, Jira, DingTalk documents, Confluence, and knowledge folders. Use when deciding what a connector reads, how imported data enters analysis, or how to describe data source limitations.
---

# Data Ingestion Semantics

Use this skill to reason about what a source means after it enters NexaFlow.

## Source Semantics

- Local CSV/XLSX/XLS: user-provided report data. It can become an ImportedReport and enter the selected task.
- Tableau View/Worksheet export: view-level crosstab export. It is not guaranteed to be the full underlying data source.
- Jira: project status evidence. Issue times and status changes are not actual release times unless confirmed.
- DingTalk documents/sheets: internal document evidence. Document update time is not business event time.
- Confluence: knowledge/project record evidence. Page time is not launch time.
- External reference source: public or manual evidence used for context and attribution checks.

## Workflow

1. Identify source type and business-space binding.
2. State whether the source becomes a report table, knowledge entry, project evidence, or external evidence.
3. Preserve source metadata: title, URL/path, created/updated/collected/imported time, permissions, and limitations.
4. State whether the data can support facts, project evidence, weak context, or only a lead.
5. Do not cross business-space boundaries unless a source is explicitly global.

## Connector Setup Fields

- Tableau: Base URL, Site Content URL, PAT Name, PAT Token, project/workbook/view filters.
- Jira: Base URL, auth type, email/user when required, token, project key, optional JQL.
- DingTalk: Client ID, Client Secret, AgentId, operatorId, folder links/IDs, optional filters.
- Confluence: Base URL, root IDs, title keywords, Bearer token, max pages.

## Output Requirements

- State what the source becomes in NexaFlow: report table, knowledge, project evidence, document evidence, or external evidence.
- State source metadata, permissions, business-space scope, and analysis limitations.

## Boundaries

- Never include tokens in AI prompts, logs, reports, or examples.
- Do not imply that a synced document proves a product change was released.
- Do not treat Tableau view filters as complete-data guarantees.
