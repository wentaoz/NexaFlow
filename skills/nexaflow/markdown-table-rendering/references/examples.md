# Markdown Table Rendering Examples

## Good input

```markdown
| 指标 | 本期 | 上期 | 变化 |
|---|---:|---:|---:|
| 注册量 | 1,200 | 1,000 | +20.00% |
```

## Output expectation

- Render as a real table in chat or Word.
- Preserve right alignment for numeric columns when the target renderer supports it.
- Keep `+20.00%` as-is because it already follows the percentage rule.

## Malformed rows

If a row has fewer cells than the header, keep it in a warning note:

`第 3 行表格列数不一致，已保留为原文。`
