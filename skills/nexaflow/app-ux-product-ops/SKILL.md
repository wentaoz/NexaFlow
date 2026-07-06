---
name: app-ux-product-ops
description: Explain and improve NexaFlow app workflows for fintech product managers and product operations users. Use when designing user-facing flows, report range selection, quick answer vs deep analysis behavior, button meanings, or whether user questions enter reports.
---

# App UX Product Ops

Use this skill to keep NexaFlow understandable for product managers and operators.

## Workflow

1. Preserve the main flow: import/select data -> ask AI -> verify what AI read -> generate concise or complete report.
2. Hide advanced concepts unless they are needed: SQL, Notebook, MCP, connector logs, memory scope.
3. Use labels that explain outcomes, not implementation details.
4. Separate quick answer, deep analysis, concise report, and complete report.
5. For report scope, choose at generation time and support selecting multiple business questions.
6. Treat UI/tool/debug questions as excluded from reports unless the user explicitly includes them.

## UX Rules

- Buttons should have one visual feedback layer.
- Sidebars should open smoothly and not block chat.
- Long AI output should be collapsible with readable tables.
- Every connector/source should state what it proves and what it does not prove.

## Output Requirements

- Give the user-facing wording first.
- Explain any advanced behavior in one short paragraph.
- Include edge cases for first-time users and returning users.

## Boundaries

- Do not change the product from an AI product/operations workbench into a BI or notebook-first tool.
- Do not expose low-level implementation as required user knowledge.

## References

Read `references/product-ops-patterns.md` for wording and interaction patterns.
