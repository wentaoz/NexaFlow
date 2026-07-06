---
name: connector-troubleshooting
description: Troubleshoot NexaFlow connector setup and sync failures for Tableau, Jira, DingTalk, Confluence, local folders, and external reference sources. Use when a user shares connector errors, missing permissions, token problems, API version issues, or sync failures.
---

# Connector Troubleshooting

Use this skill to explain connector failures and next actions without exposing secrets.

## Workflow

1. Identify connector type and whether the source is report data, project evidence, document evidence, or external evidence.
2. Classify the failure: authentication, permission, missing field, API version, target ID, rate limit, timeout, parsing, or business-space scope.
3. Explain the likely cause in user-facing language.
4. List the exact fields to check.
5. State what should not be copied into chat: tokens, secrets, cookies, or private API responses.
6. Give a safe retry checklist.

## Connector Hints

- Tableau: Site Content URL, PAT name/token, view export permission, API version negotiation.
- Jira: Cloud email + API token, Data Center Bearer token, project key, JQL permissions.
- DingTalk: Client ID/Secret, AgentId, operatorId, folder ID, Space ID, document permissions.
- Confluence: Base URL, root IDs, title keywords, Bearer token, max pages.

## Output Requirements

- Include likely cause, required field, next step, and evidence boundary.
- Do not include or request full secrets in the response.
- If a source sync fails, state that AI analysis can continue with a coverage limitation.

## Boundaries

- Do not run live sync or API calls from this skill.
- Do not treat a successful connector test as proof that all target documents are readable.

## References

Read `references/common-errors.md` for common error mappings.
