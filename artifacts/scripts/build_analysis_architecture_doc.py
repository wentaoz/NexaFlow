from __future__ import annotations

import html
import zipfile
from datetime import datetime, timezone
from pathlib import Path


OUT = Path("/Users/WilliamChang/Documents/Playground/IterationPilot/artifacts/docs/产品迭代驾驶舱_技术架构与SkillPack说明.docx")


NS_W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"


def esc(text: str) -> str:
    return html.escape(text, quote=False)


def run(text: str, bold: bool = False, color: str | None = None, size: int | None = None, font: str | None = None) -> str:
    props = []
    if bold:
        props.append("<w:b/>")
    if color:
        props.append(f'<w:color w:val="{color}"/>')
    if size:
        props.append(f'<w:sz w:val="{size * 2}"/>')
        props.append(f'<w:szCs w:val="{size * 2}"/>')
    if font:
        props.append(f'<w:rFonts w:ascii="{font}" w:hAnsi="{font}" w:eastAsia="{font}" w:cs="{font}"/>')
    rpr = f"<w:rPr>{''.join(props)}</w:rPr>" if props else ""
    preserve = ' xml:space="preserve"' if text.startswith(" ") or text.endswith(" ") else ""
    return f"<w:r>{rpr}<w:t{preserve}>{esc(text)}</w:t></w:r>"


def paragraph(
    text: str = "",
    style: str | None = None,
    bold: bool = False,
    color: str | None = None,
    size: int | None = None,
    num_id: int | None = None,
    ilvl: int = 0,
    keep_next: bool = False,
    spacing_after: int | None = None,
) -> str:
    ppr = []
    if style:
        ppr.append(f'<w:pStyle w:val="{style}"/>')
    if num_id is not None:
        ppr.append(f"<w:numPr><w:ilvl w:val=\"{ilvl}\"/><w:numId w:val=\"{num_id}\"/></w:numPr>")
    if keep_next:
        ppr.append("<w:keepNext/>")
    if spacing_after is not None:
        ppr.append(f'<w:spacing w:after="{spacing_after}"/>')
    ppr_xml = f"<w:pPr>{''.join(ppr)}</w:pPr>" if ppr else ""
    return f"<w:p>{ppr_xml}{run(text, bold=bold, color=color, size=size)}</w:p>"


def rich_paragraph(parts: list[tuple[str, bool]], style: str | None = None, spacing_after: int | None = None) -> str:
    ppr = []
    if style:
        ppr.append(f'<w:pStyle w:val="{style}"/>')
    if spacing_after is not None:
        ppr.append(f'<w:spacing w:after="{spacing_after}"/>')
    ppr_xml = f"<w:pPr>{''.join(ppr)}</w:pPr>" if ppr else ""
    return f"<w:p>{ppr_xml}{''.join(run(text, bold=bold) for text, bold in parts)}</w:p>"


def code_block(text: str) -> str:
    lines = text.strip("\n").splitlines()
    cells = "".join(paragraph(line, style="Code") for line in lines)
    return (
        '<w:tbl>'
        '<w:tblPr><w:tblW w:w="9360" w:type="dxa"/>'
        '<w:tblInd w:w="120" w:type="dxa"/>'
        '<w:tblBorders>'
        '<w:top w:val="single" w:sz="4" w:space="0" w:color="DADCE0"/>'
        '<w:left w:val="single" w:sz="4" w:space="0" w:color="DADCE0"/>'
        '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="DADCE0"/>'
        '<w:right w:val="single" w:sz="4" w:space="0" w:color="DADCE0"/>'
        '</w:tblBorders></w:tblPr>'
        '<w:tblGrid><w:gridCol w:w="9360"/></w:tblGrid>'
        '<w:tr><w:tc><w:tcPr><w:tcW w:w="9360" w:type="dxa"/>'
        '<w:shd w:fill="F7F9FB"/><w:tcMar><w:top w:w="120" w:type="dxa"/><w:bottom w:w="120" w:type="dxa"/>'
        '<w:start w:w="160" w:type="dxa"/><w:end w:w="160" w:type="dxa"/></w:tcMar></w:tcPr>'
        f"{cells}</w:tc></w:tr></w:tbl>"
    )


def table(headers: list[str], rows: list[list[str]], widths: list[int]) -> str:
    def cell(text: str, width: int, header: bool = False) -> str:
        fill = '<w:shd w:fill="F2F4F7"/>' if header else ""
        paras = [paragraph(line, bold=header, spacing_after=40) for line in text.split("\n")]
        return (
            f'<w:tc><w:tcPr><w:tcW w:w="{width}" w:type="dxa"/>{fill}'
            '<w:tcMar><w:top w:w="100" w:type="dxa"/><w:bottom w:w="100" w:type="dxa"/>'
            '<w:start w:w="140" w:type="dxa"/><w:end w:w="140" w:type="dxa"/></w:tcMar>'
            '</w:tcPr>'
            f"{''.join(paras)}</w:tc>"
        )

    grid = "".join(f'<w:gridCol w:w="{w}"/>' for w in widths)
    header_row = "<w:tr>" + "".join(cell(h, widths[i], True) for i, h in enumerate(headers)) + "</w:tr>"
    body_rows = []
    for row in rows:
        body_rows.append("<w:tr>" + "".join(cell(row[i], widths[i], False) for i in range(len(headers))) + "</w:tr>")
    return (
        '<w:tbl><w:tblPr><w:tblW w:w="9360" w:type="dxa"/><w:tblInd w:w="120" w:type="dxa"/>'
        '<w:tblBorders>'
        '<w:top w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
        '<w:left w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
        '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
        '<w:right w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
        '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
        '<w:insideV w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>'
        '</w:tblBorders></w:tblPr>'
        f"<w:tblGrid>{grid}</w:tblGrid>{header_row}{''.join(body_rows)}</w:tbl>"
    )


def doc_xml(body: str) -> str:
    return f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="{NS_W}" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <w:body>
    {body}
    <w:sectPr>
      <w:pgSz w:w="12240" w:h="15840"/>
      <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/>
    </w:sectPr>
  </w:body>
</w:document>'''


def styles_xml() -> str:
    return f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="{NS_W}">
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
    <w:name w:val="Normal"/>
    <w:pPr><w:spacing w:after="120" w:line="264" w:lineRule="auto"/></w:pPr>
    <w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Microsoft YaHei" w:cs="Calibri"/><w:sz w:val="22"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Title">
    <w:name w:val="Title"/>
    <w:pPr><w:spacing w:after="160"/></w:pPr>
    <w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Microsoft YaHei"/><w:b/><w:color w:val="0B2545"/><w:sz w:val="40"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Subtitle">
    <w:name w:val="Subtitle"/>
    <w:pPr><w:spacing w:after="240"/></w:pPr>
    <w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Microsoft YaHei"/><w:color w:val="64748B"/><w:sz w:val="22"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading1">
    <w:name w:val="Heading 1"/>
    <w:basedOn w:val="Normal"/>
    <w:next w:val="Normal"/>
    <w:pPr><w:keepNext/><w:spacing w:before="320" w:after="160"/></w:pPr>
    <w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Microsoft YaHei"/><w:b/><w:color w:val="2E74B5"/><w:sz w:val="32"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading2">
    <w:name w:val="Heading 2"/>
    <w:basedOn w:val="Normal"/>
    <w:next w:val="Normal"/>
    <w:pPr><w:keepNext/><w:spacing w:before="240" w:after="120"/></w:pPr>
    <w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Microsoft YaHei"/><w:b/><w:color w:val="2E74B5"/><w:sz w:val="26"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading3">
    <w:name w:val="Heading 3"/>
    <w:basedOn w:val="Normal"/>
    <w:next w:val="Normal"/>
    <w:pPr><w:keepNext/><w:spacing w:before="160" w:after="80"/></w:pPr>
    <w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Microsoft YaHei"/><w:b/><w:color w:val="1F4D78"/><w:sz w:val="24"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Code">
    <w:name w:val="Code"/>
    <w:pPr><w:spacing w:after="20" w:line="240" w:lineRule="auto"/></w:pPr>
    <w:rPr><w:rFonts w:ascii="Menlo" w:hAnsi="Menlo" w:eastAsia="Microsoft YaHei"/><w:sz w:val="18"/></w:rPr>
  </w:style>
</w:styles>'''


def numbering_xml() -> str:
    return f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:numbering xmlns:w="{NS_W}">
  <w:abstractNum w:abstractNumId="1">
    <w:multiLevelType w:val="hybridMultilevel"/>
    <w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="•"/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl>
  </w:abstractNum>
  <w:num w:numId="1"><w:abstractNumId w:val="1"/></w:num>
  <w:abstractNum w:abstractNumId="2">
    <w:multiLevelType w:val="hybridMultilevel"/>
    <w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl>
  </w:abstractNum>
  <w:num w:numId="2"><w:abstractNumId w:val="2"/></w:num>
</w:numbering>'''


def content_types() -> str:
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
  <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
  <Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>'''


def root_rels() -> str:
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>'''


def document_rels() -> str:
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>
</Relationships>'''


def core_xml() -> str:
    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    return f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:title>产品迭代驾驶舱：技术架构与 Skill Pack 说明</dc:title>
  <dc:creator>Codex</dc:creator>
  <cp:lastModifiedBy>Codex</cp:lastModifiedBy>
  <dcterms:created xsi:type="dcterms:W3CDTF">{now}</dcterms:created>
  <dcterms:modified xsi:type="dcterms:W3CDTF">{now}</dcterms:modified>
</cp:coreProperties>'''


def app_xml() -> str:
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
  <Application>Codex</Application>
</Properties>'''


def settings_xml() -> str:
    return f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:settings xmlns:w="{NS_W}">
  <w:zoom w:percent="100"/>
  <w:defaultTabStop w:val="720"/>
  <w:compat/>
</w:settings>'''


def build_body() -> str:
    b: list[str] = []
    b.append(paragraph("产品迭代驾驶舱：技术架构与 Skill Pack 说明", style="Title"))
    b.append(paragraph("面向海外金融产品经理和产品运营的 AI 产品迭代分析工作台", style="Subtitle"))

    b.append(paragraph("1. 一句话定位", style="Heading1"))
    b.append(rich_paragraph([
        ("产品迭代驾驶舱不是通用 ChatGPT 壳，也不是传统 BI。它是一个面向海外金融业务的 ", False),
        ("AI 分析会话工作台", True),
        ("：用户导入表格、选择本次分析表、直接向 AI 提问，系统在后台组织业务空间、知识库、Confluence、外部情报、智能记忆和本地 SQL 计算证据，最终生成可汇报的老板版报告和机会评分。", False),
    ]))
    b.append(paragraph("普通用户不需要理解 SQL、Notebook、采集日志或 Prompt。它们作为后台能力提升可信度和可回溯性。", num_id=1))

    b.append(paragraph("2. 产品架构", style="Heading1"))
    b.append(code_block("""
产品经理 / 产品运营
    ↓
分析会话工作台
    ↓
导入表格 → 选择本次分析表 → 直接问 AI → 生成老板版报告
    ↓
后台证据层：业务空间 + 表格事实包 + 知识库/Confluence + 外部情报 + 智能记忆 + DuckDB Notebook
    ↓
大模型输出：会话回答 / 报告 / 机会评分 / 补数清单
"""))
    b.append(table(
        ["层级", "核心模块", "作用"],
        [
            ["主流程层", "分析会话工作台", "承载导入、选表、提问、追问、生成报告，是普通用户的主要入口。"],
            ["业务上下文层", "业务空间、业务地图、指标语义", "约束 AI 的国家、业务域、链路、指标口径和合规边界。"],
            ["数据事实层", "CSV/XLSX/XLS 解析、覆盖快照", "说明 AI 读到了哪些表、字段、指标和周期，避免漏读或误读。"],
            ["证据增强层", "DuckDB SQL Runtime、Notebook Run", "用本地只读 SQL 计算关键指标，形成可回溯计算证据。"],
            ["外部参照层", "竞品、政策、新闻、天气、能源、社会事件", "按业务空间和分析周期采集外部证据，并记录来源和时间依据。"],
            ["智能记忆层", "纠偏、指标口径、分析偏好、报告偏好", "让后续分析继承用户确认过的口径，避免重复犯错。"],
            ["AI 生成层", "金融 Prompt Policy、大模型", "基于证据包解释业务变化、提出假设、形成报告和机会评分。"],
        ],
        [1500, 2300, 5560],
    ))

    b.append(paragraph("3. 分析会话阶段的端到端原理", style="Heading1"))
    steps = [
        "用户在会话里输入问题，例如“分析 5/24-5/30 本地生活数据变化和异常原因”。",
        "系统轻量入队 AI Job，先让界面立即响应，不在点击瞬间做重计算。",
        "后台构建上下文：读取当前任务选中的表、业务空间、知识库、记忆、外部证据和历史会话需求。",
        "如果是完整分析或报告模式，触发 Notebook/SQL 计算证据生成，并按分析周期采集外部证据。",
        "系统把覆盖快照、SQL 结果、外部证据和业务约束合并成金融分析 Prompt。",
        "大模型输出回答或老板版报告，并标明事实、推断、假设、需补数据。",
        "回答下方展示 AI 读取范围、引用证据、计算证据、补数清单，用户可以继续追问或纠偏。",
    ]
    for s in steps:
        b.append(paragraph(s, num_id=2))

    b.append(paragraph("4. Skill Pack 是什么", style="Heading1"))
    b.append(paragraph("这里的 Skill Pack 是 App 内部的分析策略层，不是让用户手动选择的插件。它根据用户问题判断分析类型，再决定要组织什么上下文、运行哪些计算、给 AI 什么输出结构。"))
    b.append(table(
        ["Skill", "适用问题", "主要策略"],
        [
            ["MetricDiagnosticsSkill", "为什么指标变化、哪里异常、转化断点在哪", "优先诊断指标变化、趋势、漏斗断点、周期差异和多表联动异常。"],
            ["ProductBusinessAnalysisSkill", "机会在哪里、该怎么优化、优先做什么", "把数据变化转成产品/运营动作，强调影响用户、收益、成本和风险。"],
            ["KPIReportingSkill", "老板版报告、周报、经营复盘", "组织执行摘要、关键指标、证据、结论分级、补数清单和行动建议。"],
            ["KPIDesignSkill", "应该看哪些指标、主指标和护栏指标如何设计", "根据业务空间建议指标体系、监控框架、口径和验证路径。"],
            ["DataQualityReasoningSkill", "字段/周期/口径是否有问题", "检查缺失、重复、异常值、日期列候选、周期口径和表格结构风险。"],
            ["VisualizationRecommendationSkill", "该用什么图或表展示", "推荐趋势图、漏斗、贡献拆解表、对比表和报告中的表格表达。"],
        ],
        [2300, 3100, 3960],
    ))

    b.append(paragraph("5. 调度路由怎么工作", style="Heading1"))
    b.append(code_block("""
用户问题
  ↓
AnalysisSkillRouter
  ↓
识别意图：异常诊断 / 产品分析 / 报告 / 指标设计 / 数据质量 / 图表建议
  ↓
生成 AnalysisSkillPlan
  ↓
决定：要算什么、要召回什么证据、要给 AI 什么输出约束
  ↓
DuckDB 执行计算 + 大模型生成解释
"""))
    b.append(paragraph("第一版路由采用确定性规则和上下文判断：关键词、当前模式、是否生成报告、当前任务选表、业务空间类型共同决定 Skill。这样可解释、稳定、便于产品经理理解。"))

    b.append(paragraph("6. Notebook / SQL 计算证据层", style="Heading1"))
    b.append(paragraph("Notebook/SQL 不改变产品定位。它不是给普通用户写 SQL 的入口，而是 AI 的后台可验证计算层。"))
    b.append(table(
        ["机制", "实现", "价值"],
        [
            ["本地 DuckDB", "把当前任务选中的报表装载为临时 raw table，并为透视宽表生成 metric/period/value long view。", "关键数字本地计算，不依赖 AI 口算，减少错算。"],
            ["只读 SQL 安全校验", "只允许 SELECT/WITH，禁止 DROP、DELETE、UPDATE、INSERT、ATTACH、COPY、INSTALL、LOAD、read_csv、httpfs 等。", "避免写入、外部文件访问和扩展加载风险。"],
            ["Notebook Run", "记录 SQL Cell、结果预览、来源报表、错误、限制。", "用户可以回溯“这个结论怎么算出来的”。"],
            ["计算证据 Tab", "在 分析资料 > 计算证据 中展示本轮 Notebook。", "高级用户可以审查 SQL 和结果，普通用户不受打扰。"],
        ],
        [2100, 4200, 3060],
    ))

    b.append(paragraph("7. 为什么难", style="Heading1"))
    for item in [
        "真实业务表不标准：宽表、长表、多 Sheet、多表头、重复列名、不同日期格式、横向周期和竖向日期列都会出现。",
        "AI 容易看错或说过头：如果没有覆盖说明和计算证据，AI 可能漏指标、误判周期或把弱证据当强因果。",
        "外部证据时间复杂：事件发生时间、内容发布时间和采集时间必须区分，否则会用当前新闻解释历史波动。",
        "多业务空间必须隔离：墨西哥信用卡、印度小贷、基金、券商的链路、数据源和记忆不能互相污染。",
        "体验必须简单：后台有 SQL、Notebook、外部采集和记忆，但用户仍只应面对会话式提问和报告输出。",
    ]:
        b.append(paragraph(item, num_id=1))

    b.append(paragraph("8. 创新点", style="Heading1"))
    b.append(table(
        ["创新点", "说明"],
        [
            ["业务空间驱动", "不同国家、产品形态、业务域有独立背景、业务地图、指标语义、数据源和记忆。"],
            ["AI + SQL 双层分析", "AI 负责解释和决策建议，DuckDB 负责关键数字计算，Notebook 留下证据链。"],
            ["外部事件可回溯归因", "每条外部证据都记录 URL、发布时间、采集时间、发生时间、证据等级和限制。"],
            ["会话式纠偏记忆", "用户在对话中纠正 AI，系统可沉淀成后续同业务空间可复用的纠偏规则。"],
            ["老板版报告直出", "不是停留在聊天，而是输出结构化报告、机会评分和 Word 文档。"],
        ],
        [2600, 6760],
    ))

    b.append(paragraph("9. 与 ChatGPT / 通用智能体助理的区别", style="Heading1"))
    b.append(table(
        ["维度", "通用 ChatGPT / 助理", "产品迭代驾驶舱"],
        [
            ["数据组织", "依赖用户临时粘贴或上传，容易漏上下文。", "按业务空间、任务、表格、知识库、数据源和记忆组织证据。"],
            ["计算可信度", "容易靠模型口算或概括。", "关键计算由本地 DuckDB 执行，Notebook 留证据。"],
            ["业务连续性", "会话之间难以稳定继承业务口径。", "纠偏、指标语义、分析偏好可沉淀到业务空间。"],
            ["外部证据", "通常需要用户手动搜索或贴链接。", "可按分析周期采集外部证据并记录采集日志。"],
            ["输出形态", "主要是聊天答案。", "面向产品/运营的报告、机会评分、补数清单和证据链。"],
        ],
        [1700, 3830, 3830],
    ))

    b.append(paragraph("10. 当前边界与后续方向", style="Heading1"))
    for item in [
        "第一版 Notebook 是 App 内分析记录，不是完整 Jupyter/Python 环境。",
        "第一版不开放普通用户自由写 SQL，避免把产品变成 SQL IDE。",
        "AI 仍是最终分析和报告作者，本地 SQL 负责计算证据，不替代业务判断。",
        "后续可以逐步开放结构化 ComputationRequest：AI 提出计算请求，本地校验后执行，失败后让 AI 修正。",
        "后续还可以增加图表证据、SQL 结果图形化、报告中引用 Notebook Cell 的跳转能力。",
    ]:
        b.append(paragraph(item, num_id=1))

    b.append(paragraph("11. 给老板的总结话术", style="Heading1"))
    b.append(rich_paragraph([
        ("这个产品的最大价值是把产品运营分析从“人手动找表、查资料、问 AI、整理报告”升级为“", False),
        ("AI 会话 + 业务证据链 + 可验证计算", True),
        ("”的一体化工作台。它不要求业务同学学 SQL，也不把自己变成 BI；它把复杂的数据读取、外部情报、记忆和计算都放在后台，让产品和运营能更快得到可解释、可汇报、可追溯的分析结果。", False),
    ]))
    return "\n".join(b)


def write_docx() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(OUT, "w", compression=zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", content_types())
        z.writestr("_rels/.rels", root_rels())
        z.writestr("word/document.xml", doc_xml(build_body()))
        z.writestr("word/_rels/document.xml.rels", document_rels())
        z.writestr("word/styles.xml", styles_xml())
        z.writestr("word/numbering.xml", numbering_xml())
        z.writestr("word/settings.xml", settings_xml())
        z.writestr("docProps/core.xml", core_xml())
        z.writestr("docProps/app.xml", app_xml())


if __name__ == "__main__":
    write_docx()
    print(OUT)
