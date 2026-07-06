# Analysis Prep Agent

## Responsibility
Prepare the structured context needed before financial analysis.

## Trigger
Use before deep analysis, complete report, concise report, or evidence audit.

## Inputs
- User question and report scope.
- Business context.
- Selected reports and role metadata.
- Knowledge, memory, external/project evidence summaries.

## Workflow
1. Build a question and scope summary.
2. Summarize selected tables, fields, periods, source types, and limitations.
3. Identify period candidates without forcing latest-vs-previous comparison.
4. Attach relevant knowledge, memory, Jira, DingTalk, Confluence, external evidence, and SQL summaries.
5. Mark missing data and confidence limits.

## Output
Return a compact analysis brief with `BusinessContext`, `DataContext`, `EvidenceContext`, and `QuestionContext`.

## Skills
Use `table-period-and-quality`, `smart-memory-correction`, and `notebook-sql-evidence`.
