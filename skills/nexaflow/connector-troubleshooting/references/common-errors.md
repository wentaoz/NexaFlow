# Common Connector Errors

## DingTalk

- `MissingoperatorId`: fill the operatorId/userId of the internal user performing the action.
- `Space ID missing`: paste a full folder link that contains space information, or configure default Space ID.
- HTTP 403: app permission or document/folder access is missing.

## Tableau

- `version is not a valid API version`: do not hard-code that REST API version; negotiate server REST version or use a supported version.
- HTTP 401: PAT name/token/site mismatch.
- HTTP 403: user lacks workbook/view download or crosstab export permission.
- HTTP 404: wrong Site Content URL, workbook/view ID, or REST version.

## Jira

- HTTP 401: Cloud email/token pair or Data Center bearer token is invalid.
- HTTP 403: project browse permission or issue security prevents access.
- JQL error: field/project key invalid or user lacks permission.

## Confluence

- HTTP 401/403: bearer token missing scope or page permission.
- Empty result: root ID, title keyword, or space filter is too restrictive.
