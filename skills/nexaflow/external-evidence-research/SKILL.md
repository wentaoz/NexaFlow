---
name: external-evidence-research
description: Plan and evaluate external evidence for NexaFlow fintech analysis, including news, regulation, competitor, app reviews, weather, holidays, macro data, and manual sources. Use when deciding whether external evidence supports an attribution or how to describe source coverage.
---

# External Evidence Research

Use this skill to keep external evidence useful but bounded.

## Evidence Time Basis

- Event time: strongest basis for attribution.
- Published time: medium basis when event time is absent.
- Collected time: weak basis; useful as a lead only.
- No relevant time: background only.

## Workflow

1. Identify the analysis period. If the user specified a period, evidence queries must target that period.
2. Separate active collection from cached evidence.
3. Group evidence by competitor, regulation, news/finance, market, social/review, natural/social event, or manual source.
4. Mark each item with source name, title, URL, event time, published time, collected time, and limitation.
5. Use only matching-window evidence for high-confidence attribution.
6. Put uncovered sources and failed collection into limitations.

## Source Scope

- Candidate sources are not used until tested or enabled.
- Current business-space sources and explicit global sources can be used.
- Unbound or other-space sources must not enter analysis.
- Manual sources need clear notes; otherwise they are leads, not evidence.

## Output Requirements

- List source name, title, URL, event time, published time, collected time, evidence level, and limitation.
- Separate active collection, cached evidence, candidate sources, skipped sources, and failed sources.

## Boundaries

- Do not use current news to explain a historical period unless the date basis matches.
- Do not hide weak evidence; show why it is weak.
- Do not treat search result availability as proof that an event happened.
