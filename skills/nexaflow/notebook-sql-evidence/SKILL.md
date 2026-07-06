---
name: notebook-sql-evidence
description: Design and review local SQL/Notebook calculation evidence for NexaFlow analysis. Use when a conclusion needs reproducible computation, when explaining how a number was calculated, or when validating SQL-backed metric tables.
---

# Notebook SQL Evidence

Use this skill to plan safe, local, read-only calculations that support analysis.

## Workflow

1. Define the calculation goal: comparison, trend, contribution, funnel break, cohort, segment, quality check, or validation.
2. Identify selected task tables only. Do not use unselected reports.
3. Use safe read-only SQL: SELECT and WITH only.
4. Keep results small and analysis-ready. Return summaries, not huge extracts.
5. Link every result to table names, fields, filters, period logic, and limitations.
6. If SQL fails, return schema/error and mark calculation as incomplete; do not invent numbers.

## Safe SQL Rules

- Allow SELECT and WITH.
- Reject DROP, DELETE, UPDATE, INSERT, ATTACH, COPY, INSTALL, LOAD, filesystem reads, network extensions, and writes.
- Limit execution time, result rows, memory, and output size.
- Preserve original field mappings when safe SQL names differ from source headers.

## Report Usage

- Use SQL results for key metric tables, linkage tables, funnel breaks, data quality, and validation rows.
- Summarize SQL in Word-ready output; keep full SQL in calculation evidence.
- Distinguish SQL-verified facts from AI inferences.
