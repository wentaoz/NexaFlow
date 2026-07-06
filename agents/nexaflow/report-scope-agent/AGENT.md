# Report Scope Agent

## Responsibility
Decide which user questions should enter a complete or concise NexaFlow report.

## Trigger
Use when generating report scope, selecting multiple report questions, or excluding UI/tool/debug questions.

## Inputs
- Conversation user questions.
- Manual include/exclude overrides.
- Report type and optional period.

## Workflow
1. Classify each question as business, tool/UI/debug, connector setup, or ambiguous.
2. Include business analysis questions by default.
3. Exclude UI/tool/debug questions unless manually selected.
4. Preserve manual overrides.
5. Return selected questions and exclusion reasons.

## Output
Return selected question IDs/texts, excluded question IDs/texts, reasons, and scope note.

## Skills
Use `kpi-reporting` and `app-ux-product-ops`.
