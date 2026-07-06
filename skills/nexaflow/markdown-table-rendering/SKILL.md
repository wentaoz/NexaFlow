---
name: markdown-table-rendering
description: Convert NexaFlow AI markdown tables into readable tables for chat, reports, Word export, and evidence review. Use when markdown output is hard to read, when tables need fixed columns, or when report tables must preserve structure.
---

# Markdown Table Rendering

Use this skill to make analytical markdown tables readable without changing the underlying analysis.

## Workflow

1. Detect markdown pipe tables, list-like tables, and pseudo tables from AI output.
2. Normalize headers, separators, row counts, and escaped pipe characters.
3. Preserve business meaning: metric names, periods, evidence levels, source names, URLs, and limitations.
4. Convert wide tables into scrollable UI tables or Word-safe tables when needed.
5. If a table is too wide, keep the primary columns visible and move secondary details into row expansion or notes.
6. Do not rewrite numbers except applying NexaFlow formatting rules already required by the report.

## Output Requirements

- Keep table headers concise.
- Keep percentages and percentage points to exactly two decimals.
- Preserve links and source labels.
- Mark malformed rows instead of silently dropping them.
- For Word output, prefer real table blocks over plain markdown.

## Boundaries

- Do not reinterpret the analysis.
- Do not aggregate, calculate, or infer missing values.
- Do not hide weak evidence or limitations to make a table look cleaner.

## References

Read `references/examples.md` for conversion examples and failure cases.
