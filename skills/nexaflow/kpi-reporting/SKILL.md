---
name: kpi-reporting
description: Create NexaFlow complete reports and concise daily reports for fintech product and operations audiences. Use when producing leadership updates, WBR/MBR-style summaries, period recaps, complete reports, concise reports, or Word-ready report briefs.
---

# KPI Reporting

Use this skill to produce report briefs or report text that matches NexaFlow's reporting semantics.

## Report Types

- Complete report: full leadership-ready report with scope, AI read coverage, data coverage, metric changes, drivers, evidence, risks, opportunities, and actions.
- Concise report: daily operating update with only period data changes, cause analysis, and action recommendations.

## Workflow

1. Lock report scope: full conversation, selected questions, or one custom period.
2. List covered questions at the start. Exclude UI/tool/debug questions unless manually included.
3. State period policy. If no period is specified, write "full-period overview" and avoid forcing a main comparison.
4. Rebuild the evidence basis conceptually: selected tables, knowledge, Confluence, DingTalk, Jira, external evidence, memory, and SQL/Notebook summaries.
5. Write the report using the selected report type. Do not reuse quick-answer text as final report evidence without revalidating it against the current scope.
6. Add missing-data items for unsupported claims.

## Complete Report Structure

1. Report type, scope, covered questions, period policy.
2. Executive summary.
3. AI read coverage.
4. Data coverage and limitations.
5. Key metric changes.
6. Driver analysis and multi-table evidence.
7. External and project evidence.
8. Facts, inferences, hypotheses, and missing data.
9. Opportunities and action plan.

## Concise Report Structure

1. Period data changes.
2. Cause analysis.
3. Action recommendations.

## Output Requirements

- Start with report type, scope, covered questions, and period policy.
- Include AI read coverage in complete reports.
- Keep concise reports limited to the three daily-report sections.

## Boundaries

- Do not call concise reports "complete reports".
- Do not include lengthy SQL or raw logs in Word-ready output; summarize and point to calculation evidence.
- Do not include superseded AI conclusions after a user correction.
- Format percentages and percentage points to two decimals.

## References

Read `../_shared/report-brief-example.md` for a compact complete-report brief example.
