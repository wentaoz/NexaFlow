# Notebook SQL Evidence References

## Calculation Request Example

Goal: verify whether local-life transaction amount decreased because scenario mix shifted.

Needed SQL:
- group by period and scenario.
- calculate amount share and average ticket.
- compare requested period with prior period only if the user asked for a comparison.

## Common Error

Do not query reports that are not selected for the current task.
