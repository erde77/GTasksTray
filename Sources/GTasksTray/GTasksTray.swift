import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@main
enum GTasksTray {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = TaskStore()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var statusSubscription: AnyCancellable?
    private var syncTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: nil)
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePanel)
        }
        statusItem = item
        statusSubscription = store.$groups.combineLatest(store.$connection, store.$hasLoaded, store.$language)
            .sink { [weak self] groups, connection, hasLoaded, language in
                self?.updateStatusItem(groups: groups, showCount: connection == .connected && hasLoaded, language: language)
        }

        popover.behavior = .transient
        popover.contentSize = NSSize(width: PanelStyle.width, height: PanelStyle.height)
        popover.contentViewController = NSHostingController(
            rootView: TasksPanel(store: store, chooseClient: { [weak self] in self?.chooseClient() })
        )

        syncTask = Task { [weak store] in
            while !Task.isCancelled {
                await store?.refresh()
                do {
                    try await Task.sleep(for: .seconds(90))
                } catch {
                    break
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        syncTask?.cancel()
        store.cancelSignIn()
    }

    private func updateStatusItem(groups: [TaskGroup], showCount: Bool, language: AppLanguage) {
        guard let button = statusItem?.button else { return }
        let count = TaskStore.openCount(in: groups)
        button.title = showCount ? " \(count)" : ""
        button.toolTip = showCount ? language.format("Google Tasks · Open tasks: %ld", count) : "Google Tasks"
        button.setAccessibilityLabel(button.toolTip)
    }

    @objc private func togglePanel() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = statusItem?.button, !popover.isShown else { return }
        activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        Task { await store.refresh() }
    }

    private func chooseClient() {
        popover.close()
        activate()
        let panel = NSOpenPanel()
        let language = store.language
        panel.title = language.text("Choose an OAuth client file")
        panel.message = language.text("Select the JSON file downloaded from Google Cloud for a Desktop app client.")
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            store.importClient(from: url)
        }
        showPanel()
    }

    private func activate() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
