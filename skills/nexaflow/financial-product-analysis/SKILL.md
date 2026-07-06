---
name: financial-product-analysis
description: Analyze overseas fintech product and operations questions for lending, credit card, fund, and brokerage businesses. Use when the user asks why a metric changed, what product or operating action to take, how funnel/risk/channel/activity data connects, or how to explain financial product performance with evidence.
---

# Financial Product Analysis

Use this skill to turn product/operations questions into evidence-backed analysis for overseas fintech businesses.

## Workflow

1. Clarify the business question: growth, acquisition, registration, KYC, approval, credit line, activation, transaction, retention, repeat usage, repayment, overdue, risk, revenue, cost, channel quality, compliance, or market impact.
2. State the data read: selected reports, fields, periods, source type, and whether each table was full, sampled, profiled, or aggregated.
3. Separate facts, inferences, hypotheses, and missing data.
4. Link drivers across upstream, core, and downstream tables. Use report roles only to organize evidence; do not ignore fields in supporting tables.
5. Include external/project evidence only when its time basis is clear. Jira, DingTalk, and Confluence are project/document evidence, not proof of actual release.
6. End with action recommendations and validation data needed.

## Financial Focus

- Credit card: acquisition, application, KYC/SMS, approval, credit line, card issuance, activation, first transaction, ongoing spend, repayment, delinquency, complaints.
- Lending: acquisition, registration, identity verification, risk scoring, loan application, approval, disbursement, repayment, repeat borrowing, delinquency, collection.
- Fund/brokerage: account opening, deposit, trading, AUM, redemption, retention, suitability, market volatility, compliance boundaries.

## Output Requirements

- Start with a direct answer when the user asks a focused question.
- Show "AI read coverage" for any deep analysis.
- Do not force a latest-period comparison unless the user asked for one.
- Use "needs data" instead of suggesting the user asks another question when the missing input is a table, field, period, or external evidence.
- Format percentages and percentage points to two decimals.

## Boundaries

- Do not give investment advice or return promises.
- Do not suggest bypassing KYC, compliance, risk rules, or platform controls.
- Do not treat document update time, Jira status time, or collection time as actual event time.
- If accepted correction memory conflicts with older AI conclusions, use the correction.

## References

Read `../_shared/financial-output-policy.md` when checking output quality.
