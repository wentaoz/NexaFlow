---
name: table-period-and-quality
description: Inspect table shape, period semantics, long-table/wide-table patterns, date candidates, and data quality risks for NexaFlow analysis. Use when preparing table facts, explaining why a period was chosen, or checking whether AI can trust a table.
---

# Table Period and Quality

Use this skill to describe table facts without overfitting to one rigid table layout.

## Table Shape Rules

- Wide pivot table: metrics in first column, periods across columns.
- Long table: period/date, metric, segment, and value columns.
- Detail table: one row per entity/event, often with multiple date columns.
- Mixed table: requires candidate interpretation and user confirmation.

## Period Rules

1. Treat local period detection as candidates, not final business truth.
2. Sort period ranges by end date when possible.
3. Do not default to latest vs previous unless the user asked for comparison.
4. If the user specifies a period, keep that as the highest-priority scope.
5. If no period is specified, describe a full-period overview.

## Workflow

1. Identify table shape and grain.
2. Extract period/date candidates and source examples.
3. Describe row/column counts, metrics, fields, and source limitations.
4. Mark quality risks without blocking analysis unless the table is unusable.
5. Hand period candidates to AI as candidates, not final business truth.

## Quality Checks

- Missing rows, duplicated keys, missing periods, inconsistent denominators.
- Unclear grain: user, transaction, account, application, card, channel, or day/week/month.
- Multiple date columns that change the business meaning.
- Aggregated exports that hide raw rows or filters.
- Versioned source data that may have changed since prior analysis.

## Output Requirements

- State row/column counts, fields, period candidates, source type, and coverage mode.
- Mark uncertain date/period columns as candidates.
- Explain data quality risks as limitations, not blockers, unless the table is unusable.
- Ask for a specific missing field/table only when it changes the conclusion.

## Boundaries

- Do not treat local period detection as final truth.
- Do not force a comparison when the user asked for overview.
- Do not hide view/export filters or aggregation limitations.
