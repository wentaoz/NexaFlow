---
name: smart-memory-correction
description: Use NexaFlow correction memory and smart memory rules for repeated analysis preferences, metric definitions, business logic, and report corrections. Use when a user corrects an AI conclusion, says to remember a rule, or asks whether old corrected content can enter a report.
---

# Smart Memory Correction

Use this skill to protect accepted user corrections and reusable business rules.

## Memory Types

- Correction rule: what was wrong, corrected conclusion, future reuse rule.
- Metric definition: how a metric should be calculated or interpreted.
- Analysis preference: preferred comparison, evidence hierarchy, or output style.
- Report preference: structure, wording, scope, and audience requirements.
- Business-link rule: upstream/downstream relationship.
- External attribution rule: how to treat outside events and weak evidence.

## Workflow

1. Give current user instruction highest priority.
2. Use current-session confirmed scope/metric definitions before long-term memory.
3. Apply accepted correction rules before knowledge, templates, and AI inference.
4. If old AI content conflicts with correction memory, mark old content as superseded.
5. Do not turn "save to knowledge" into a correction memory unless the user explicitly accepts it.
6. Show memory hits and conflicts when the output depends on them.

## Report Rules

- Do not include corrected-away AI conclusions as final report conclusions.
- If a confirmed metric definition exists, do not list it as missing data.
- If memory conflicts, ask for or state the conflict rather than silently choosing.

## Output Requirements

- Return memory type, scope, corrected conclusion, reuse rule, and report exclusion effect.
- State whether a memory is accepted, candidate-only, superseded, or conflicting.

## Boundaries

- Memory is scoped to the same business space unless explicitly global.
- Draft or unaccepted candidates should not pollute future analysis.
