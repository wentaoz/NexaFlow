import SwiftUI

struct BusinessSpacesView: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    @State private var showCreateBusinessSpaceSheet = false
    @State private var showBasicConfiguration = false
    @State private var showArchiveConfirmation = false
    @State private var showBusinessDomainCreateSheet = false
    @State private var showBusinessDomainLinkCreateSheet = false
    @State private var businessMapScrollTarget: String?
    @State private var resetTemplate: BusinessSpace?
    @State private var pendingSpaceDrafts: [UUID: BusinessSpace] = [:]
    @State private var spaceCommitTask: Task<Void, Never>?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let space = store.selectedBusinessSpace {
                        let draft = draftedSpace(space)
                        background(draft)
                        basicConfiguration(draft)
                        businessMap(draft)
                        confluenceRoots(draft)
                        BusinessSpaceDataSourceActions(spaceID: draft.id)
                            .equatable()
                    } else {
                        EmptyStateView(
                            title: "还没有业务空间",
                            detail: "创建一个业务空间后，再导入表格和 AI 对话分析。",
                            systemImage: "globe.asia.australia"
                        )
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: businessMapScrollTarget) { target in
                guard let target else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                    businessMapScrollTarget = nil
                }
            }
        }
        .sheet(isPresented: $showCreateBusinessSpaceSheet) {
            CreateBusinessSpaceSheet(
                hasConfiguredAI: store.hasConfiguredAI,
                createAction: { draft in
                    store.createBusinessSpace(
                        name: draft.name,
                        businessBackground: draft.businessBackground
                    )
                }
            )
            .environmentObject(store)
        }
        .sheet(isPresented: $showBusinessDomainCreateSheet) {
            if let space = store.selectedBusinessSpace {
                BusinessDomainCreateSheet(existingNames: space.domains.map(\.name)) { domain in
                    mutateSpace(space.id, commitImmediately: true) { space in
                        space.domains.append(domain)
                    }
                    businessMapScrollTarget = businessDomainAnchor(domain.id)
                }
            }
        }
        .sheet(isPresented: $showBusinessDomainLinkCreateSheet) {
            if let space = store.selectedBusinessSpace {
                BusinessDomainLinkCreateSheet(domains: space.domains) { link in
                    mutateSpace(space.id, commitImmediately: true) { space in
                        space.domainLinks.append(link)
                    }
                    businessMapScrollTarget = businessLinkAnchor(link.id)
                }
            }
        }
        .onDisappear {
            flushSpaceDraftsToStore()
        }
    }

    private var header: some View {
        ResponsiveStack(compactBreakpoint: 720, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("业务空间")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("业务空间决定 AI 会在哪个国家、业务域、知识库、Confluence Root Page 和参照数据源范围内分析。示例只辅助填写，不会锁死业务模板。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Picker("业务空间", selection: Binding(
                    get: { store.selectedBusinessSpace?.id },
                    set: {
                        flushSpaceDraftsToStore()
                        store.selectBusinessSpace($0)
                    }
                )) {
                    ForEach(store.activeBusinessSpaces) { space in
                        Text(space.name).tag(Optional(space.id))
                    }
                }
                .frame(width: 220)
                .hoverControlShell(.pickerShell)

                Button {
                    showCreateBusinessSpaceSheet = true
                } label: {
                    Label("新建业务空间", systemImage: "plus")
                }
                .help("打开弹窗填写自然语言业务背景；确认前不会创建新记录")

                Menu {
                    Button {
                        flushSpaceDraftsToStore()
                        store.restoreBuiltInBusinessSpaces()
                    } label: {
                        Label("恢复内置业务空间", systemImage: "arrow.clockwise")
                    }
                    Divider()
                    ForEach(BuiltInBusinessSpaceCatalog.spaces, id: \.builtInKey) { template in
                        Button {
                            flushSpaceDraftsToStore()
                            store.createBusinessSpaceFromBuiltIn(template)
                        } label: {
                            Text("从「\(template.name)」新建")
                        }
                    }
                    if store.selectedBusinessSpace != nil {
                        Divider()
                        Menu("高级操作：覆盖当前空间配置") {
                            ForEach(BuiltInBusinessSpaceCatalog.spaces, id: \.builtInKey) { template in
                                Button {
                                    flushSpaceDraftsToStore()
                                    resetTemplate = template
                                } label: {
                                    Text("用「\(template.name)」模板覆盖当前空间配置...")
                                }
                            }
                        }
                    }
                } label: {
                    Label("内置业务空间", systemImage: "building.columns")
                }
                .hoverControlShell(.pickerShell)
                .help("恢复或复制内置海外金融业务空间；高级覆盖只改当前空间配置，不删除数据包、会话或知识")

                if store.selectedBusinessSpace != nil {
                    Button(role: .destructive) {
                        showArchiveConfirmation = true
                    } label: {
                        Label("归档", systemImage: "archivebox")
                    }
                    .buttonStyle(AppHoverButtonStyle(variant: .danger))
                    .disabled(store.activeBusinessSpaces.count <= 1)
                    .help(store.activeBusinessSpaces.count <= 1 ? "至少需要保留一个业务空间" : "归档当前业务空间；历史会话、数据包和知识不会被删除")
                }
            }
        }
        .confirmationDialog(
            "归档当前业务空间？",
            isPresented: $showArchiveConfirmation,
            titleVisibility: .visible
        ) {
            if let space = store.selectedBusinessSpace {
                Button("归档「\(space.name)」", role: .destructive) {
                    flushSpaceDraftsToStore()
                    store.archiveBusinessSpace(space)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("归档后它会从业务空间切换器中隐藏；关联数据包、分析会话、知识库和数据源记录会保留，避免工作记忆丢失。")
        }
        .confirmationDialog(
            "用内置模板覆盖当前空间配置？",
            isPresented: Binding(
                get: { resetTemplate != nil },
                set: { if !$0 { resetTemplate = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let resetTemplate, let current = store.selectedBusinessSpace {
                Button("覆盖为「\(resetTemplate.name)」配置", role: .destructive) {
                    flushSpaceDraftsToStore()
                    store.resetBusinessSpaceToBuiltIn(resetTemplate, targetID: current.id)
                    self.resetTemplate = nil
                }
            }
            Button("取消", role: .cancel) {
                resetTemplate = nil
            }
        } message: {
            Text("会覆盖：空间名称、国家/地区、时区、币种、语言、业务背景、业务地图、指标分类、异常规则、分析边界和推荐源类别。会保留：数据包、会话、知识库、Confluence Root Page、指标语义、参照数据源和采集日志。")
        }
    }

    private func basicConfiguration(_ space: BusinessSpace) -> some View {
        SectionCard(title: "AI 已识别的基础配置", systemImage: "person.text.rectangle") {
            DisclosureGroup(isExpanded: $showBasicConfiguration) {
                VStack(spacing: 10) {
                    ResponsiveFormRow("业务空间名称") {
                        TextField("例如：墨西哥 App", text: stringBinding(space.id, \.name))
                            .textFieldStyle(.roundedBorder)
                    }
                    ResponsiveFormRow("国家/地区") {
                        TextField("例如：墨西哥、菲律宾、哥伦比亚", text: stringBinding(space.id, \.countryRegion))
                            .textFieldStyle(.roundedBorder)
                    }
                    ResponsiveStack(compactBreakpoint: 700, spacing: 10) {
                        ResponsiveFormRow("时区") {
                            TextField("例如：America/Mexico_City", text: stringBinding(space.id, \.timeZoneIdentifier))
                                .textFieldStyle(.roundedBorder)
                        }
                        ResponsiveFormRow("币种") {
                            TextField("例如：MXN", text: stringBinding(space.id, \.currencyCode))
                                .textFieldStyle(.roundedBorder)
                        }
                        ResponsiveFormRow("主要语言") {
                            TextField("例如：zh-CN, es-MX, en", text: stringBinding(space.id, \.primaryLanguagesText))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    Text("这些字段主要用于时间换算、货币展示、外部数据源地区过滤和 AI 分析范围。普通使用时只需要检查 AI 是否识别正确。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text([space.countryRegion.nilIfBlank, space.timeZoneIdentifier.nilIfBlank, space.currencyCode.nilIfBlank, space.primaryLanguagesText.nilIfBlank]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                        .nilIfBlank ?? "未识别基础配置")
                        .fontWeight(.medium)
                    Text(store.hasConfiguredAI ? "由自然语言背景识别，可展开修改。" : "未配置 AI 时使用本地默认或空值，可展开检查。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func background(_ space: BusinessSpace) -> some View {
        SectionCard(title: "自然语言业务背景", systemImage: "text.bubble") {
            VStack(alignment: .leading, spacing: 12) {
                Text("把国家、产品形态、业务域、核心流程、指标口径、外部影响和 AI 禁区写清楚。AI 会基于这段内容生成业务地图，但你仍可手动修改。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                AdaptiveTextBox(
                    text: stringBinding(space.id, \.businessBackground),
                    placeholder: BusinessSpace.backgroundPromptTemplate,
                    minHeight: 180,
                    maxHeight: 420
                )

                HStack(spacing: 8) {
                    ForEach(BusinessSpaceExampleKind.allCases) { kind in
                        Button(kind.label) {
                            flushSpaceDraftsToStore()
                            store.insertBusinessSpaceExample(kind, into: space.id)
                        }
                    }
                }
                .buttonStyle(AppHoverButtonStyle(variant: .secondary))

                HStack(spacing: 8) {
                    Button {
                        flushSpaceDraftsToStore()
                        store.generateBusinessMapForSelectedSpace()
                    } label: {
                        Label("AI 生成业务地图", systemImage: "sparkles")
                    }
                    .buttonStyle(AppHoverButtonStyle(variant: .primary))

                    Button {
                        flushSpaceDraftsToStore()
                        store.recommendReferenceSourcesForSelectedBusinessSpace()
                    } label: {
                        Label("AI 推荐数据源", systemImage: "wand.and.stars")
                    }
                }
            }
        }
    }

    private func businessMap(_ space: BusinessSpace) -> some View {
        SectionCard(title: "可编辑业务地图", systemImage: "point.3.connected.trianglepath.dotted") {
            VStack(alignment: .leading, spacing: 14) {
                ResponsiveFormRow("业务地图摘要") {
                    AdaptiveTextBox(
                        text: stringBinding(space.id, \.generatedSummary),
                        placeholder: "AI 生成后会写入业务地图摘要；也可以手动编辑。",
                        minHeight: 90,
                        maxHeight: 260
                    )
                }

                Divider()

                Label("业务域和关系只帮助 AI 组织证据、判断主次和联动路径，不会限制 AI 读取表格里的所有字段和指标。", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text("业务域")
                        .font(.headline)
                    Spacer()
                    Button {
                        showBusinessDomainCreateSheet = true
                    } label: {
                        Label("新增业务域", systemImage: "plus")
                    }
                    .buttonStyle(AppHoverButtonStyle(variant: .secondary))
                    .help("打开弹窗填写业务域，保存前不会创建空白业务域")
                }

                ForEach(space.domains) { domain in
                    businessDomainEditor(spaceID: space.id, domain: domain)
                        .id(businessDomainAnchor(domain.id))
                }

                Divider()

                HStack {
                    Text("跨业务影响关系")
                        .font(.headline)
                    Spacer()
                    Button {
                        showBusinessDomainLinkCreateSheet = true
                    } label: {
                        Label("新增关系", systemImage: "plus")
                    }
                    .buttonStyle(AppHoverButtonStyle(variant: .secondary))
                    .disabled(space.domains.count < 2)
                    .help(space.domains.count < 2 ? "至少需要 2 个业务域后才能建立影响关系" : "打开弹窗选择来源、目标和影响机制")
                }

                ForEach(space.domainLinks) { link in
                    businessLinkEditor(spaceID: space.id, link: link)
                        .id(businessLinkAnchor(link.id))
                }

                Divider()

                ResponsiveFormRow("指标分类规则") {
                    AdaptiveTextBox(text: stringBinding(space.id, \.metricClassificationRulesText), minHeight: 110, maxHeight: 280)
                }
                ResponsiveFormRow("常见异常解释") {
                    AdaptiveTextBox(text: stringBinding(space.id, \.anomalyRulesText), minHeight: 110, maxHeight: 280)
                }
                ResponsiveFormRow("分析禁区") {
                    AdaptiveTextBox(text: stringBinding(space.id, \.analysisGuardrailsText), minHeight: 110, maxHeight: 280)
                }
            }
        }
    }

    private func businessDomainEditor(spaceID: UUID, domain: BusinessDomain) -> some View {
        let roleBinding = domainRoleBinding(spaceID: spaceID, domainID: domain.id)
        return VStack(alignment: .leading, spacing: 8) {
            ResponsiveStack(compactBreakpoint: 680, spacing: 10) {
                TextField("业务域名称", text: domainStringBinding(spaceID: spaceID, domainID: domain.id, \.name))
                    .textFieldStyle(.roundedBorder)
                Picker("角色", selection: roleBinding) {
                    ForEach(BusinessDomainRole.allCases) { role in
                        Text(role.label).tag(role)
                    }
                }
                .frame(width: 150)
                .hoverControlShell(.pickerShell)
                .help(roleBinding.wrappedValue.explanation)
                Button(role: .destructive) {
                    mutateSpace(spaceID, commitImmediately: true) { space in
                        space.domains.removeAll { $0.id == domain.id }
                        space.domainLinks.removeAll { $0.sourceDomainID == domain.id || $0.targetDomainID == domain.id }
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(AppHoverButtonStyle(variant: .danger))
                .help("删除业务域")
            }
            Label(roleBinding.wrappedValue.explanation, systemImage: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            AdaptiveTextField(placeholder: "业务域说明", text: domainStringBinding(spaceID: spaceID, domainID: domain.id, \.description), minLines: 1, maxLines: 3)
            AdaptiveTextBox(
                text: domainStringBinding(spaceID: spaceID, domainID: domain.id, \.coreFlowText),
                placeholder: "核心链路，例如：获客 → 注册 → 申请 → 审批 → 授信 → 发卡 → 首刷",
                minHeight: 64,
                maxHeight: 160
            )
        }
        .padding(10)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    private func businessLinkEditor(spaceID: UUID, link: BusinessDomainLink) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ResponsiveStack(compactBreakpoint: 700, spacing: 8) {
                TextField("来源业务域", text: linkStringBinding(spaceID: spaceID, linkID: link.id, \.sourceName))
                    .textFieldStyle(.roundedBorder)
                TextField("目标业务域", text: linkStringBinding(spaceID: spaceID, linkID: link.id, \.targetName))
                    .textFieldStyle(.roundedBorder)
                Button(role: .destructive) {
                    mutateSpace(spaceID, commitImmediately: true) { space in
                        space.domainLinks.removeAll { $0.id == link.id }
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(AppHoverButtonStyle(variant: .danger))
                .help("删除关系")
            }
            AdaptiveTextBox(
                text: linkStringBinding(spaceID: spaceID, linkID: link.id, \.influenceMechanism),
                placeholder: "影响机制，例如：信用卡新客激活后可能带来本地生活缴费交叉使用。",
                minHeight: 64,
                maxHeight: 180
            )
            AdaptiveTextField(placeholder: "证据规则", text: linkStringBinding(spaceID: spaceID, linkID: link.id, \.evidenceRule), minLines: 1, maxLines: 3)
        }
        .padding(10)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    private func confluenceRoots(_ space: BusinessSpace) -> some View {
        SectionCard(title: "Confluence Root Page", systemImage: "doc.text.magnifyingglass") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Root Page 绑定业务域后，Confluence 检索会优先使用当前业务空间、业务域、Root Page 子树和标题排除词。通用词不能单独判断业务域。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button {
                        mutateSpace(space.id, commitImmediately: true) { space in
                            space.confluenceRoots.append(BusinessSpaceConfluenceRoot())
                        }
                    } label: {
                        Label("新增 Root Page", systemImage: "plus")
                    }
                    .buttonStyle(AppHoverButtonStyle(variant: .secondary))
                }
                ForEach(space.confluenceRoots) { root in
                    confluenceRootEditor(spaceID: space.id, root: root)
                }
            }
        }
    }

    private func confluenceRootEditor(spaceID: UUID, root: BusinessSpaceConfluenceRoot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ResponsiveStack(compactBreakpoint: 720, spacing: 8) {
                TextField("Root Page ID", text: rootStringBinding(spaceID: spaceID, rootID: root.id, \.rootPageID))
                    .textFieldStyle(.roundedBorder)
                TextField("显示名称", text: rootStringBinding(spaceID: spaceID, rootID: root.id, \.title))
                    .textFieldStyle(.roundedBorder)
                Button(role: .destructive) {
                    mutateSpace(spaceID, commitImmediately: true) { space in
                        space.confluenceRoots.removeAll { $0.id == root.id }
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(AppHoverButtonStyle(variant: .danger))
            }
            AdaptiveTextField(placeholder: "标题关键字，逗号或换行分隔。不要只填申请/审批/放款这种通用词。", text: rootStringBinding(spaceID: spaceID, rootID: root.id, \.titleKeywordsText), minLines: 1, maxLines: 3)
            AdaptiveTextField(placeholder: "排除词，逗号或换行分隔", text: rootStringBinding(spaceID: spaceID, rootID: root.id, \.exclusionKeywordsText), minLines: 1, maxLines: 3)
            AdaptiveTextField(placeholder: "备注", text: rootStringBinding(spaceID: spaceID, rootID: root.id, \.notes), minLines: 1, maxLines: 3)
        }
        .padding(10)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    private func stringBinding(_ spaceID: UUID, _ keyPath: WritableKeyPath<BusinessSpace, String>) -> Binding<String> {
        Binding(
            get: { draftedSpace(id: spaceID)?[keyPath: keyPath] ?? "" },
            set: { newValue in
                mutateSpace(spaceID) { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func domainStringBinding(
        spaceID: UUID,
        domainID: UUID,
        _ keyPath: WritableKeyPath<BusinessDomain, String>
    ) -> Binding<String> {
        Binding(
            get: {
                draftedSpace(id: spaceID)?
                    .domains.first(where: { $0.id == domainID })?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                mutateSpace(spaceID) { space in
                    guard let index = space.domains.firstIndex(where: { $0.id == domainID }) else { return }
                    space.domains[index][keyPath: keyPath] = newValue
                }
            }
        )
    }

    private func domainRoleBinding(spaceID: UUID, domainID: UUID) -> Binding<BusinessDomainRole> {
        Binding(
            get: {
                draftedSpace(id: spaceID)?
                    .domains.first(where: { $0.id == domainID })?.role ?? .supporting
            },
            set: { newValue in
                mutateSpace(spaceID, commitImmediately: true) { space in
                    guard let index = space.domains.firstIndex(where: { $0.id == domainID }) else { return }
                    space.domains[index].role = newValue
                }
            }
        )
    }

    private func linkStringBinding(
        spaceID: UUID,
        linkID: UUID,
        _ keyPath: WritableKeyPath<BusinessDomainLink, String>
    ) -> Binding<String> {
        Binding(
            get: {
                draftedSpace(id: spaceID)?
                    .domainLinks.first(where: { $0.id == linkID })?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                mutateSpace(spaceID) { space in
                    guard let index = space.domainLinks.firstIndex(where: { $0.id == linkID }) else { return }
                    space.domainLinks[index][keyPath: keyPath] = newValue
                }
            }
        )
    }

    private func rootStringBinding(
        spaceID: UUID,
        rootID: UUID,
        _ keyPath: WritableKeyPath<BusinessSpaceConfluenceRoot, String>
    ) -> Binding<String> {
        Binding(
            get: {
                draftedSpace(id: spaceID)?
                    .confluenceRoots.first(where: { $0.id == rootID })?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                mutateSpace(spaceID) { space in
                    guard let index = space.confluenceRoots.firstIndex(where: { $0.id == rootID }) else { return }
                    space.confluenceRoots[index][keyPath: keyPath] = newValue
                }
            }
        )
    }

    private func draftedSpace(_ space: BusinessSpace) -> BusinessSpace {
        pendingSpaceDrafts[space.id] ?? space
    }

    private func draftedSpace(id spaceID: UUID) -> BusinessSpace? {
        pendingSpaceDrafts[spaceID] ?? store.workspace.businessSpaces.first(where: { $0.id == spaceID })
    }

    private func mutateSpace(
        _ spaceID: UUID,
        commitImmediately: Bool = false,
        _ transform: (inout BusinessSpace) -> Void
    ) {
        guard var space = draftedSpace(id: spaceID) else { return }
        transform(&space)
        pendingSpaceDrafts[spaceID] = space
        if commitImmediately {
            commitSpaceDraft(spaceID)
        } else {
            scheduleSpaceDraftCommit()
        }
    }

    private func scheduleSpaceDraftCommit() {
        spaceCommitTask?.cancel()
        spaceCommitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            flushSpaceDraftsToStore()
        }
    }

    private func flushSpaceDraftsToStore() {
        spaceCommitTask?.cancel()
        spaceCommitTask = nil
        let draftIDs = Array(pendingSpaceDrafts.keys)
        for draftID in draftIDs {
            commitSpaceDraft(draftID)
        }
    }

    private func commitSpaceDraft(_ spaceID: UUID) {
        guard let draft = pendingSpaceDrafts[spaceID] else { return }
        pendingSpaceDrafts[spaceID] = nil
        guard store.workspace.businessSpaces.first(where: { $0.id == spaceID }) != draft else { return }
        store.updateBusinessSpace(draft)
    }

    private func businessDomainAnchor(_ id: UUID) -> String {
        "business-domain-\(id.uuidString)"
    }

    private func businessLinkAnchor(_ id: UUID) -> String {
        "business-link-\(id.uuidString)"
    }
}

private struct BusinessSpaceDataSourceActions: View, Equatable {
    @EnvironmentObject private var store: ProductWorkflowStore
    var spaceID: UUID

    static func == (lhs: BusinessSpaceDataSourceActions, rhs: BusinessSpaceDataSourceActions) -> Bool {
        lhs.spaceID == rhs.spaceID
    }

    var body: some View {
        SectionCard(title: "数据源候选", systemImage: "newspaper") {
            let snapshot = makeSnapshot()
            VStack(alignment: .leading, spacing: 10) {
                Text("AI 推荐的数据源会先进入候选池，不会自动参与分析。当前业务空间只会使用已绑定到本空间的数据源和显式全局源；未绑定源需要先处理。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if snapshot.unboundCount > 0 {
                    Text("待处理未绑定数据源：\(snapshot.unboundCount) 个。它们不会参与分析，请到参照数据源页绑定或标记为全局。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(snapshot.relatedSources) { source in
                    HStack(alignment: .top, spacing: 10) {
                        Badge(text: source.lifecycleStatus.label, systemImage: nil, tint: source.lifecycleStatus == .enabled ? AppTheme.success : AppTheme.warning)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.name)
                                .fontWeight(.semibold)
                            Text(source.recommendationReason.nilIfBlank ?? source.domain.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if source.lifecycleStatus != .enabled {
                            Button("启用") { store.enableReferenceSource(source) }
                                .buttonStyle(AppHoverButtonStyle(variant: .primary))
                        }
                        if source.lifecycleStatus != .ignored {
                            Button("忽略") { store.ignoreReferenceSource(source) }
                                .buttonStyle(AppHoverButtonStyle(variant: .ghost))
                        }
                    }
                    .padding(8)
                    .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                }
            }
        }
    }

    private func makeSnapshot() -> (relatedSources: [ExternalReferenceSource], unboundCount: Int) {
        var relatedSources: [ExternalReferenceSource] = []
        relatedSources.reserveCapacity(12)
        var unboundCount = 0

        for source in store.workspace.referenceSources {
            if source.isUnbound {
                unboundCount += 1
            }
            guard source.isGlobal || source.businessSpaceIDs.contains(spaceID) else { continue }
            if relatedSources.count < 12 {
                relatedSources.append(source)
            }
        }

        return (relatedSources, unboundCount)
    }
}

private struct BusinessDomainCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    var existingNames: [String]
    var onSave: (BusinessDomain) -> Void

    @State private var name = ""
    @State private var role: BusinessDomainRole = .supporting
    @State private var description = ""
    @State private var coreFlowText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("新增业务域")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("业务域用于告诉 AI 这块业务在整体链路中的位置。保存前不会创建空白业务域。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ResponsiveFormRow("业务域名称", labelWidth: 96) {
                AdaptiveTextField(placeholder: "例如：获客与注册、授信/审核、本地生活缴费", text: $name, minLines: 1, maxLines: 2)
            }

            ResponsiveFormRow("业务域角色", labelWidth: 96) {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("业务域角色", selection: $role) {
                        ForEach(BusinessDomainRole.allCases) { role in
                            Text(role.label).tag(role)
                        }
                    }
                    .labelsHidden()
                    .hoverControlShell(.pickerShell)
                    Text(role.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ResponsiveFormRow("业务域说明", labelWidth: 96) {
                AdaptiveTextField(placeholder: "说明这个业务域覆盖哪些对象、场景或指标", text: $description, minLines: 2, maxLines: 5)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("核心链路")
                    .foregroundStyle(.secondary)
                AdaptiveTextBox(
                    text: $coreFlowText,
                    placeholder: "例如：曝光 → 点击 → 安装 → 注册 → 申请 → 审批",
                    minHeight: 90,
                    maxHeight: 180
                )
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("取消", role: .cancel) {
                    dismiss()
                }
                Button {
                    let domain = BusinessDomain(
                        name: trimmedName,
                        description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                        coreFlowText: coreFlowText.trimmingCharacters(in: .whitespacesAndNewlines),
                        role: role
                    )
                    onSave(domain)
                    dismiss()
                } label: {
                    Label("保存业务域", systemImage: "checkmark.circle")
                }
                .buttonStyle(AppHoverButtonStyle(variant: .primary))
                .disabled(!canSave)
            }
        }
        .padding(22)
        .frame(width: 640)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedName: String {
        trimmedName.lowercased()
    }

    private var hasDuplicateName: Bool {
        existingNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .contains(normalizedName)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !hasDuplicateName
    }

    private var validationMessage: String? {
        if trimmedName.isEmpty {
            return "请先填写业务域名称。"
        }
        if hasDuplicateName {
            return "已存在同名业务域，请换一个更清楚的名称。"
        }
        return nil
    }
}

private struct BusinessDomainLinkCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    var domains: [BusinessDomain]
    var onSave: (BusinessDomainLink) -> Void

    @State private var sourceDomainID: UUID?
    @State private var targetDomainID: UUID?
    @State private var influenceMechanism = ""
    @State private var lagDaysText = ""
    @State private var evidenceRule = ""

    init(domains: [BusinessDomain], onSave: @escaping (BusinessDomainLink) -> Void) {
        self.domains = domains
        self.onSave = onSave
        _sourceDomainID = State(initialValue: domains.first?.id)
        _targetDomainID = State(initialValue: domains.dropFirst().first?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("新增跨业务影响关系")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("关系用于告诉 AI 哪些业务域可能互相影响。保存前不会创建空白关系。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label("如果要表达外部事件、竞品或政策影响，建议先创建一个“外部事件/竞品/政策”旁证业务域，再建立关系。", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if domains.count < 2 {
                Text("至少需要 2 个业务域后才能建立影响关系。")
                    .foregroundStyle(AppTheme.warning)
            } else {
                ResponsiveFormRow("来源业务域", labelWidth: 108) {
                    Picker("来源业务域", selection: $sourceDomainID) {
                        ForEach(domains) { domain in
                            Text(domain.name).tag(Optional(domain.id))
                        }
                    }
                    .labelsHidden()
                    .hoverControlShell(.pickerShell)
                }

                ResponsiveFormRow("目标业务域", labelWidth: 108) {
                    Picker("目标业务域", selection: $targetDomainID) {
                        ForEach(domains) { domain in
                            Text(domain.name).tag(Optional(domain.id))
                        }
                    }
                    .labelsHidden()
                    .hoverControlShell(.pickerShell)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("影响机制")
                        .foregroundStyle(.secondary)
                    AdaptiveTextBox(
                        text: $influenceMechanism,
                        placeholder: "例如：获客渠道质量下降会影响注册和申请通过率。",
                        minHeight: 90,
                        maxHeight: 180
                    )
                }

                ResponsiveFormRow("影响滞后天数", labelWidth: 108) {
                    AdaptiveTextField(placeholder: "可选，例如：1、3、7", text: $lagDaysText, minLines: 1, maxLines: 1)
                }

                ResponsiveFormRow("证据规则", labelWidth: 108) {
                    AdaptiveTextField(placeholder: "例如：需同时看到渠道结构变化和注册转化下降", text: $evidenceRule, minLines: 2, maxLines: 5)
                }
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("取消", role: .cancel) {
                    dismiss()
                }
                Button {
                    guard let link = linkFromDraft else { return }
                    onSave(link)
                    dismiss()
                } label: {
                    Label("保存关系", systemImage: "checkmark.circle")
                }
                .buttonStyle(AppHoverButtonStyle(variant: .primary))
                .disabled(!canSave)
            }
        }
        .padding(22)
        .frame(width: 660)
    }

    private var selectedSource: BusinessDomain? {
        domains.first { $0.id == sourceDomainID }
    }

    private var selectedTarget: BusinessDomain? {
        domains.first { $0.id == targetDomainID }
    }

    private var trimmedMechanism: String {
        influenceMechanism.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedLagDays: Int? {
        let text = lagDaysText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return Int(text)
    }

    private var hasInvalidLagDays: Bool {
        let text = lagDaysText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && Int(text) == nil
    }

    private var canSave: Bool {
        domains.count >= 2 &&
            selectedSource != nil &&
            selectedTarget != nil &&
            sourceDomainID != targetDomainID &&
            !trimmedMechanism.isEmpty &&
            !hasInvalidLagDays
    }

    private var validationMessage: String? {
        if domains.count < 2 {
            return "请先新增至少 2 个业务域。"
        }
        if sourceDomainID == targetDomainID {
            return "来源业务域和目标业务域不能相同。"
        }
        if trimmedMechanism.isEmpty {
            return "请填写影响机制。"
        }
        if hasInvalidLagDays {
            return "影响滞后天数只能填写整数。"
        }
        return nil
    }

    private var linkFromDraft: BusinessDomainLink? {
        guard let source = selectedSource, let target = selectedTarget else { return nil }
        return BusinessDomainLink(
            sourceDomainID: source.id,
            targetDomainID: target.id,
            sourceName: source.name,
            targetName: target.name,
            influenceMechanism: trimmedMechanism,
            lagDays: parsedLagDays,
            evidenceRule: evidenceRule.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

private struct BusinessSpaceCreationDraft {
    var name = ""
    var businessBackground = ""
}

private struct CreateBusinessSpaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    var hasConfiguredAI: Bool
    var createAction: (BusinessSpaceCreationDraft) -> Void

    @State private var draft = BusinessSpaceCreationDraft()
    @State private var step = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if step == 1 {
                        nameStep
                    } else {
                        backgroundStep
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            Divider()
            footer
        }
        .frame(minWidth: 620, idealWidth: 720, minHeight: 560, idealHeight: 680)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("新建业务空间")
                .font(.title2)
                .fontWeight(.semibold)
            Text("先用自然语言描述业务。创建后系统会自动识别国家、时区、币种、语言和业务地图；你之后可以展开检查。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                stepBadge(number: 1, title: "命名", isActive: step == 1, isDone: !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                stepBadge(number: 2, title: "业务背景", isActive: step == 2, isDone: !draft.businessBackground.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("1. 给这个业务空间起一个名字")
                .font(.headline)
            Text("名称只用于切换分析范围，例如“墨西哥 App”“墨西哥信用卡 + 本地生活”“菲律宾增长分析”。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("例如：墨西哥 App", text: $draft.name)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var backgroundStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("2. 用自然语言描述业务背景")
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                promptLine("这个业务在哪个国家/地区？")
                promptLine("产品是什么类型？例如金融 App、本地生活 App、综合 App。")
                promptLine("包含哪些业务域？例如信用卡、小贷、本地生活缴费、钱包、支付、风控、客服。")
                promptLine("主要链路是什么？")
                promptLine("最关心哪些指标？哪些越高越好，哪些越低越好？")
                promptLine("哪些外部事件可能影响业务？例如天气、用电、节假日、政策、竞品活动。")
            }
            .padding(10)
            .background(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            AdaptiveTextBox(
                text: $draft.businessBackground,
                placeholder: BusinessSpace.backgroundPromptTemplate,
                minHeight: 220,
                maxHeight: 420
            )

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { exampleButtons }
                VStack(alignment: .leading, spacing: 8) { exampleButtons }
            }
            .buttonStyle(AppHoverButtonStyle(variant: .secondary))

            if !hasConfiguredAI {
                Label("未配置 AI：创建后会使用本地规则生成草稿，基础配置需要后续展开检查。", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var exampleButtons: some View {
        ForEach(BusinessSpaceExampleKind.allCases) { kind in
            Button(kind.label) {
                draft.businessBackground = kind.background
                if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    draft.name == "新业务空间" {
                    draft.name = kind.defaultName
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("取消") {
                dismiss()
            }
            Spacer()
            if step == 2 {
                Button("上一步") {
                    step = 1
                }
            }
            Button(step == 1 ? "下一步" : (hasConfiguredAI ? "创建并识别" : "创建")) {
                if step == 1 {
                    step = 2
                } else {
                    createAction(draft)
                    dismiss()
                }
            }
            .buttonStyle(AppHoverButtonStyle(variant: .primary))
            .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16)
    }

    private func stepBadge(number: Int, title: String, isActive: Bool, isDone: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "\(number).circle")
                .foregroundStyle(isDone ? AppTheme.success : (isActive ? AppTheme.accent : .secondary))
            Text(title)
                .fontWeight(isActive ? .semibold : .regular)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background((isActive ? AppTheme.accent : Color.secondary).opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private func promptLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
