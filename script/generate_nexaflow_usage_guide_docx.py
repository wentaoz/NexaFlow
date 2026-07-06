#!/usr/bin/env python3
"""Generate a simple Word document from the NexaFlow usage guide markdown.

This intentionally uses only the Python standard library so the repository does
not need a document-generation dependency for this static guide.
"""

from __future__ import annotations

import html
import re
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs" / "nexaflow-skill-agent-mcp-usage-guide.md"
TARGET = ROOT / "docs" / "nexaflow-skill-agent-mcp-usage-guide.docx"


def esc(text: str) -> str:
    return html.escape(text, quote=False)


def paragraph(text: str, style: str | None = None) -> str:
    style_xml = f'<w:pPr><w:pStyle w:val="{style}"/></w:pPr>' if style else ""
    return f"<w:p>{style_xml}<w:r><w:t xml:space=\"preserve\">{esc(text)}</w:t></w:r></w:p>"


def code_paragraph(text: str) -> str:
    return (
        "<w:p><w:pPr><w:pStyle w:val=\"Code\"/></w:pPr>"
        f"<w:r><w:rPr><w:rFonts w:ascii=\"Menlo\" w:eastAsia=\"Menlo\"/></w:rPr><w:t xml:space=\"preserve\">{esc(text)}</w:t></w:r></w:p>"
    )


def table(rows: list[list[str]]) -> str:
    grid_cols = "".join('<w:gridCol w:w="2400"/>' for _ in range(max(len(row) for row in rows)))
    out = [
        "<w:tbl>",
        "<w:tblPr><w:tblStyle w:val=\"TableGrid\"/><w:tblW w:w=\"0\" w:type=\"auto\"/></w:tblPr>",
        f"<w:tblGrid>{grid_cols}</w:tblGrid>"
    ]
    for row in rows:
        out.append("<w:tr>")
        for cell in row:
            out.append(f"<w:tc><w:tcPr><w:tcW w:w=\"2400\" w:type=\"dxa\"/></w:tcPr>{paragraph(cell)}</w:tc>")
        out.append("</w:tr>")
    out.append("</w:tbl>")
    return "".join(out)


def parse_table_line(line: str) -> list[str]:
    stripped = line.strip().strip("|")
    return [cell.strip().replace("`", "") for cell in stripped.split("|")]


def is_separator(line: str) -> bool:
    return bool(re.match(r"^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$", line))


def render_body(markdown: str) -> str:
    lines = markdown.splitlines()
    body: list[str] = []
    i = 0
    in_code = False
    while i < len(lines):
        line = lines[i]
        if line.startswith("```"):
            in_code = not in_code
            i += 1
            continue
        if in_code:
            body.append(code_paragraph(line))
            i += 1
            continue
        if line.strip().startswith("|") and i + 1 < len(lines) and is_separator(lines[i + 1]):
            rows = [parse_table_line(line)]
            i += 2
            while i < len(lines) and lines[i].strip().startswith("|"):
                rows.append(parse_table_line(lines[i]))
                i += 1
            body.append(table(rows))
            continue
        if line.startswith("# "):
            body.append(paragraph(line[2:].strip(), "Title"))
        elif line.startswith("## "):
            body.append(paragraph(line[3:].strip(), "Heading1"))
        elif line.startswith("### "):
            body.append(paragraph(line[4:].strip(), "Heading2"))
        elif line.startswith("- "):
            body.append(paragraph("• " + line[2:].strip()))
        elif re.match(r"^\d+\.\s+", line):
            body.append(paragraph(line.strip()))
        elif not line.strip():
            body.append(paragraph(""))
        else:
            body.append(paragraph(line.strip()))
        i += 1
    return "".join(body)


def write_docx(document_xml: str) -> None:
    content_types = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>"""
    rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>"""
    document_rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>"""
    styles = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:rPr><w:b/><w:sz w:val="36"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:rPr><w:b/><w:sz w:val="28"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:rPr><w:b/><w:sz w:val="24"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Code"><w:name w:val="Code"/><w:rPr><w:rFonts w:ascii="Menlo" w:eastAsia="Menlo"/><w:sz w:val="18"/></w:rPr></w:style>
  <w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/><w:tblPr><w:tblBorders><w:top w:val="single" w:sz="4" w:space="0" w:color="D0D7DE"/><w:left w:val="single" w:sz="4" w:space="0" w:color="D0D7DE"/><w:bottom w:val="single" w:sz="4" w:space="0" w:color="D0D7DE"/><w:right w:val="single" w:sz="4" w:space="0" w:color="D0D7DE"/><w:insideH w:val="single" w:sz="4" w:space="0" w:color="D0D7DE"/><w:insideV w:val="single" w:sz="4" w:space="0" w:color="D0D7DE"/></w:tblBorders></w:tblPr></w:style>
</w:styles>"""
    doc = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>{document_xml}<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1080" w:bottom="1440" w:left="1080" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr></w:body>
</w:document>"""
    with zipfile.ZipFile(TARGET, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("[Content_Types].xml", content_types)
        archive.writestr("_rels/.rels", rels)
        archive.writestr("word/_rels/document.xml.rels", document_rels)
        archive.writestr("word/styles.xml", styles)
        archive.writestr("word/document.xml", doc)


def main() -> None:
    document_xml = render_body(SOURCE.read_text(encoding="utf-8"))
    write_docx(document_xml)
    print(TARGET)


if __name__ == "__main__":
    main()
