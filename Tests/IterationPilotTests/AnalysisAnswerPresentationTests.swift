import XCTest
@testable import IterationPilotCore

final class AnalysisAnswerPresentationTests: XCTestCase {
    func testParsesDirectAnswerAndMovesSupportingSectionsOutOfChatBody() throws {
        let markdown = """
        ## 直接回答你的问题
        交易人数由 19,462 人增至 32,136 人，增长 65.12%。

        ## 本地已校验事实
        | 指标 | 2025 H2 | 2026 H1 |
        |---|---:|---:|
        | 交易人数 | 19,462 | 32,136 |

        ## 关键数据证据
        派生指标按 SUM 分子 / SUM 分母重算。

        ## AI 读取到的数据
        表结构为指标-周期-值。

        ## 未覆盖/需补数据
        2026 H1 非完整半年度。
        """

        let presentation = try XCTUnwrap(AnalysisAnswerPresentation.parse(markdown))

        XCTAssert(presentation.answerMarkdown.contains("增长 65.12%"))
        XCTAssert(!presentation.answerMarkdown.contains("AI 读取到的数据"))
        XCTAssert(presentation.supportingSections.map(\.title).contains("本地已校验事实"))
        XCTAssert(presentation.supportingSections.map(\.kind).contains(.calculationEvidence))
        XCTAssert(presentation.supportingSections.map(\.kind).contains(.readScope))
        XCTAssert(presentation.supportSummaryText.contains("本地校验"))
        XCTAssert(presentation.supportSummaryText.contains("读取范围"))
    }
    func testReturnsNilForLegacyMessagesWithoutDirectAnswerHeading() {
        let legacyMarkdown = """
        这是一条历史回答，没有标准章节。

        ## 数据说明
        历史内容仍应完整展示。
        """

        XCTAssert(AnalysisAnswerPresentation.parse(legacyMarkdown) == nil)
    }
    func testAcceptsDirectAnswerSynonymHeading() throws {
        let markdown = """
        ## 直接结论
        主回答仍然应该被识别。

        ## AI 读取到的数据
        表。
        """

        let presentation = try XCTUnwrap(AnalysisAnswerPresentation.parse(markdown))

        XCTAssert(presentation.answerMarkdown == "主回答仍然应该被识别。")
        XCTAssert(presentation.supportingSections.first?.kind == .readScope)
    }
    func testHandlesReorderedSupportingSections() throws {
        let markdown = """
        ## AI 读取到的数据
        先输出了读取范围。

        ## 未覆盖/需补数据
        有一个限制。

        ## 直接回答你的问题
        结论仍然应该进入主回答。

        ## 资料证据
        本轮没有外部资料。
        """

        let presentation = try XCTUnwrap(AnalysisAnswerPresentation.parse(markdown))

        XCTAssert(presentation.answerMarkdown == "结论仍然应该进入主回答。")
        XCTAssert(presentation.supportingSections.count == 3)
        XCTAssert(presentation.supportingSections.first?.kind == .readScope)
        XCTAssert(presentation.supportingSections.contains { $0.kind == .limitations })
        XCTAssert(presentation.supportingSections.contains { $0.kind == .materialEvidence })
    }
    func testAcceptsHeadingWithoutSpaceAfterHashes() throws {
        let markdown = """
        ## 直接回答你的问题
        主回答。

        ##9. 关键数据证据
        这段应被移到依据区。
        """

        let presentation = try XCTUnwrap(AnalysisAnswerPresentation.parse(markdown))

        XCTAssert(presentation.answerMarkdown == "主回答。")
        XCTAssert(presentation.supportingSections.count == 1)
        XCTAssert(presentation.supportingSections.first?.kind == .calculationEvidence)
    }
}
