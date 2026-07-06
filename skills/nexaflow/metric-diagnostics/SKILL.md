---
name: metric-diagnostics
description: Diagnose fintech metric movements, anomalies, funnel breaks, cohort shifts, and multi-table drivers. Use when a user asks why a KPI changed, where conversion broke, whether a channel/risk/activity change caused impact, or what data is needed to verify a metric hypothesis.
---

# Metric Diagnostics

Use this skill to diagnose a metric movement without overclaiming causality.

## Workflow

1. Identify the metric, period, comparison basis, and grain. If the user did not specify a period, use full-period overview language.
2. Reproduce or request the metric definition. Prefer SQL/Notebook evidence when available.
3. Break down movement by funnel stage, segment, channel, product, scenario, card type, customer type, region, or risk bucket.
4. Look for upstream and downstream consistency: acquisition -> registration -> KYC -> approval -> activation -> transaction -> retention/revenue/risk.
5. Classify evidence as fact, inference, hypothesis, or missing data.
6. Recommend the smallest next data request that would validate or reject the leading hypothesis.

## Diagnostic Patterns

- Funnel break: compare pass-through rates and absolute volumes by stage.
- Channel quality: compare source mix, conversion, risk rejection, activation, and downstream value.
- Risk policy impact: compare approval/rejection mix, KYC/SMS error, fraud/risk block, and later transaction/repayment.
- Campaign effect: compare eligible population, exposure, conversion, spend, repeat behavior, and ROI guardrails.
- Data issue: check denominator changes, duplicate users, missing periods, inconsistent aggregation, and source refresh timing.

## Output Requirements

- Do not present one-cause explanations when evidence only shows correlation.
- Use "needs data" for missing fields, logs, events, or periods.
- Show whether the conclusion is supported by table data, project evidence, external evidence, or memory.
- Keep quick diagnostics short unless the user asks for deep analysis.

## Boundaries

- Do not infer causality from correlation alone.
- Do not override user-specified periods with default latest-vs-previous comparisons.
- Do not recommend risk or compliance changes without guardrails and owner review.

## References

Read `../_shared/financial-output-policy.md` for evidence classification rules.
