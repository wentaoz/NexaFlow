import AppKit
import IterationPilotCore
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var retainedDelegate: AppDelegate?
    private let legacySplitFrameKey = "NSSplitView Subview Frames main-AppWindow-1, SidebarNavigationSplitView"
    private let legacyWindowFrameKey = "NSWindow Frame main-AppWindow-1"
    private let mainWindowInitialSize = NSSize(width: 1240, height: 800)
    private let mainWindowMinimumSize = NSSize(width: 1180, height: 760)
    private let store = sharedWorkflowStore
    private var mainWindow: NSWindow?
    private var mainWindowController: NSWindowController?
    private var leftTitlebarAccessory: NSTitlebarAccessoryViewController?
    private var textEditingShortcutMonitor: Any?

    static func main() {
        if AppInternalLiveSmokeRunner.isRequested {
            AppInternalLiveSmokeRunner.runAndExit()
        }
        disableAppKitStateRestoration()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        Self.disableAppKitStateRestoration()
        Self.removeSavedApplicationState()
        UserDefaults.standard.removeObject(forKey: legacySplitFrameKey)
        UserDefaults.standard.removeObject(forKey: legacyWindowFrameKey)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        AppNotificationBootstrap.configure()
        installMainMenu()
        installTextEditingShortcutMonitor()
        ensureMainWindowVisible()
        DebugSnapshotBootstrap.scheduleIfRequested(store: store, mainWindow: mainWindow)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationShouldSaveApplicationState(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldRestoreApplicationState(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        ensureMainWindowVisible()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if mainWindow?.isVisible != true {
            ensureMainWindowVisible()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private static func disableAppKitStateRestoration() {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        UserDefaults.standard.set(true, forKey: "ApplePersistenceIgnoreState")
    }

    private static func removeSavedApplicationState() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let savedStateURL = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Saved Application State", isDirectory: true)
            .appendingPathComponent("\(bundleID).savedState", isDirectory: true)
        try? FileManager.default.removeItem(at: savedStateURL)
    }

    private func ensureMainWindowVisible() {
        if mainWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: mainWindowInitialSize),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "NexaFlow"
            window.identifier = NSUserInterfaceItemIdentifier("main-AppWindow-1")
            window.isRestorable = false
            window.isReleasedWhenClosed = false
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.backgroundColor = NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(calibratedRed: 36 / 255, green: 36 / 255, blue: 36 / 255, alpha: 1)
                    : NSColor(calibratedRed: 251 / 255, green: 248 / 255, blue: 241 / 255, alpha: 1)
            }
            window.center()
            window.minSize = mainWindowMinimumSize
            window.contentView = NSHostingView(
                rootView: ContentView()
                    .environmentObject(store)
                    .frame(minWidth: mainWindowMinimumSize.width, minHeight: mainWindowMinimumSize.height)
            )
            enforceMainWindowMinimumSize(window)
            installTitlebarSidebarControls(on: window)
            mainWindowController = NSWindowController(window: window)
            mainWindow = window
        }
        mainWindowController?.showWindow(nil)
        mainWindow?.makeKeyAndOrderFront(nil)
        mainWindow?.orderFrontRegardless()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func enforceMainWindowMinimumSize(_ window: NSWindow) {
        let frame = window.frame
        let targetWidth = max(frame.width, mainWindowMinimumSize.width)
        let targetHeight = max(frame.height, mainWindowMinimumSize.height)
        guard targetWidth != frame.width || targetHeight != frame.height else { return }

        window.setFrame(
            NSRect(
                x: frame.minX,
                y: frame.maxY - targetHeight,
                width: targetWidth,
                height: targetHeight
            ),
            display: false
        )
    }

    private func installTitlebarSidebarControls(on window: NSWindow) {
        guard leftTitlebarAccessory == nil else { return }
        let accessoryHeight: CGFloat = 32

        let leftHostingView = NSHostingView(
            rootView: TitlebarSidebarToggleButton()
                .environmentObject(store)
        )
        leftHostingView.frame = NSRect(x: 0, y: 0, width: 34, height: accessoryHeight)
        leftHostingView.translatesAutoresizingMaskIntoConstraints = false
        leftHostingView.widthAnchor.constraint(equalToConstant: 34).isActive = true
        leftHostingView.heightAnchor.constraint(equalToConstant: accessoryHeight).isActive = true
        let leftAccessory = NSTitlebarAccessoryViewController()
        leftAccessory.layoutAttribute = .left
        leftAccessory.view = leftHostingView
        window.addTitlebarAccessoryViewController(leftAccessory)
        leftTitlebarAccessory = leftAccessory
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "NexaFlow")
        appMenu.addItem(
            withTitle: "退出 NexaFlow",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let workflowItem = NSMenuItem()
        let workflowMenu = NSMenu(title: "工作流")
        workflowMenu.addItem(withTitle: "导入本地表...", action: #selector(requestImport), keyEquivalent: "i")
        workflowMenu.addItem(withTitle: "重新分析当前资料", action: #selector(recomputeSelectedPack), keyEquivalent: "r")
        let memoItem = NSMenuItem(title: "生成完整汇报", action: #selector(regenerateMemoForSelectedPack), keyEquivalent: "M")
        workflowMenu.addItem(memoItem)
        workflowItem.submenu = workflowMenu
        mainMenu.addItem(workflowItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    private func installTextEditingShortcutMonitor() {
        guard textEditingShortcutMonitor == nil else { return }
        textEditingShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
                  !event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.control),
                  !event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.option),
                  let key = event.charactersIgnoringModifiers?.lowercased() else {
                return event
            }

            let selector: Selector?
            switch key {
            case "c":
                selector = #selector(NSText.copy(_:))
            case "v":
                selector = #selector(NSText.paste(_:))
            case "x":
                selector = #selector(NSText.cut(_:))
            case "a":
                selector = #selector(NSText.selectAll(_:))
            case "z":
                selector = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift) ? Selector(("redo:")) : Selector(("undo:"))
            default:
                selector = nil
            }

            guard let selector else { return event }
            guard let responder = NSApplication.shared.keyWindow?.firstResponder else { return event }
            if responder.responds(to: selector) {
                NSApplication.shared.sendAction(selector, to: nil, from: nil)
                return nil
            }
            return event
        }
    }

    @objc private func requestImport() {
        store.requestImport()
    }

    @objc private func recomputeSelectedPack() {
        store.recomputeSelectedPack()
    }

    @objc private func regenerateMemoForSelectedPack() {
        store.regenerateMemoForSelectedPack()
    }
}

private struct TitlebarSidebarToggleButton: View {
    @EnvironmentObject private var store: ProductWorkflowStore
    @Environment(\.isEnabled) private var isEnvironmentEnabled
    @State private var isHovered = false

    private var isEnabled: Bool {
        store.canToggleMainSidebarFromTitlebar
    }

    private var systemImage: String {
        "sidebar.leading"
    }

    private var helpText: String {
        if store.isAnalysisReadingMode {
            return "恢复侧栏"
        }
        return store.isMainSidebarVisible ? "隐藏侧栏" : "显示侧栏"
    }

    var body: some View {
        Button {
            store.toggleMainSidebarFromTitlebar()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.secondary)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(width: 32, height: 28)
        .background(titlebarBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(titlebarStroke, lineWidth: isHovered ? 1 : 0.8)
        }
        .scaleEffect(isHovered && isEnabled ? 0.99 : 1)
        .opacity(isEnabled ? 1 : 0.28)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .textSelection(.disabled)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            guard isEnabled else { return }
            isHovered = hovering
        }
        .help(helpText)
        .accessibilityLabel(helpText)
    }

    private var titlebarBackground: Color {
        guard isEnabled && isEnvironmentEnabled else { return .clear }
        return Color.secondary.opacity(isHovered ? 0.18 : 0.08)
    }

    private var titlebarStroke: Color {
        guard isEnabled && isEnvironmentEnabled else { return .clear }
        return Color.secondary.opacity(isHovered ? 0.32 : 0.10)
    }
}
