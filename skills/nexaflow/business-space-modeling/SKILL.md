---
name: business-space-modeling
description: Model NexaFlow business spaces, business maps, domains, roles, and built-in overseas fintech contexts. Use when creating or reviewing a business space for Mexico, India, Philippines, Indonesia, Pakistan, Kazakhstan, Nigeria, credit card, lending, fund, or brokerage analysis.
---

# Business Space Modeling

Use this skill to define the context that bounds NexaFlow analysis.

## Business Space Contents

- Country/region, timezone, currency, and language.
- Product type: credit card, lending, fund, brokerage, or other.
- Natural-language background.
- Business domains and roles.
- Business map and cross-domain links.
- Common metrics, anomalies, external influences, compliance boundaries.
- Recommended source categories, not automatically enabled sources.

## Domain Roles

- Primary domain: core operating chain. AI organizes conclusions around it.
- Supporting domain: upstream/downstream or related operational domain.
- Evidence domain: used to explain or validate movement, not standalone causality.

## Report Role Semantics

- Primary report: central outcome table.
- Driver report: upstream table that may explain movement.
- Outcome report: downstream table.
- Supporting report: background or validation evidence.
- Excluded report: not used in analysis or report.

## Workflow

1. Identify the product and country context.
2. Map the core flow: acquisition -> registration -> KYC/verification -> approval/credit -> activation/disbursement/trading -> usage/repayment/retention/risk.
3. Add country-specific external influences: regulation, payment ecosystem, holidays, weather, macro, energy, competition, app reviews.
4. Define what the AI should never assume: launch dates, legal conclusions, or unsupported causal links.

## Output Requirements

- Return business context, domain roles, business map, recommended source categories, and analysis boundaries.
- Keep built-in contexts editable and do not present them as hard-coded analysis templates.

## Boundaries

- Business space is the default isolation boundary.
- Do not mix data, sources, knowledge, or memories across business spaces unless explicitly global.
