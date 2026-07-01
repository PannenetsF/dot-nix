import AppKit
import Dispatch

private let dirtyPath = CommandLine.arguments.dropFirst().first
    ?? "/tmp/aerospace-workspace-indicator-dirty-\(getuid())"
private let aerospacePath = "/opt/homebrew/bin/aerospace"
private let debugEnabled = ProcessInfo.processInfo.environment["AEROSPACE_INDICATOR_DEBUG"] == "1"

private func debugLog(_ message: String) {
    guard debugEnabled else { return }
    let timestamp = String(format: "%.3f", Date().timeIntervalSince1970)
    fputs("[workspace-indicator] \(timestamp) \(message)\n", stderr)
}

struct MonitorState {
    let monitorName: String
    let workspace: String
    let workspaces: [String]
    let appEntries: [String]
}

final class IndicatorView: NSView {
    private let workspaceStack = NSStackView()
    private let iconStack = NSStackView()
    private var iconCache: [String: NSImage] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.34).cgColor
        layer?.cornerRadius = 13
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor

        workspaceStack.orientation = .horizontal
        workspaceStack.alignment = .centerY
        workspaceStack.spacing = 5
        workspaceStack.translatesAutoresizingMaskIntoConstraints = false

        iconStack.orientation = .horizontal
        iconStack.alignment = .centerY
        iconStack.spacing = 5
        iconStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(workspaceStack)
        addSubview(iconStack)

        NSLayoutConstraint.activate([
            workspaceStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            workspaceStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconStack.leadingAnchor.constraint(equalTo: workspaceStack.trailingAnchor, constant: 10),
            iconStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            iconStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(workspace: String, workspaces: [String], appEntries: [String]) {
        replaceArrangedSubviews(in: workspaceStack)
        for item in workspaces {
            workspaceStack.addArrangedSubview(workspaceView(item, selected: item == workspace))
        }

        replaceArrangedSubviews(in: iconStack)
        for entry in appEntries.prefix(8) {
            iconStack.addArrangedSubview(iconView(for: entry))
        }
    }

    private func replaceArrangedSubviews(in stack: NSStackView) {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func workspaceView(_ workspace: String, selected: Bool) -> NSView {
        let label = NSTextField(labelWithString: workspace)
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: selected ? .semibold : .medium)
        label.textColor = NSColor.white.withAlphaComponent(selected ? 0.95 : 0.44)
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.cornerRadius = 8
        label.layer?.backgroundColor = selected
            ? NSColor.white.withAlphaComponent(0.18).cgColor
            : NSColor.clear.cgColor
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: workspace.count > 1 ? 30 : 24),
            label.heightAnchor.constraint(equalToConstant: 24),
        ])
        return label
    }

    private func iconView(for entry: String) -> NSView {
        if entry.hasPrefix("name:") {
            return fallbackIcon(String(entry.dropFirst(5)))
        }

        let image = cachedIcon(for: entry)
        image.size = NSSize(width: 20, height: 20)

        let imageView = NSImageView(image: image)
        imageView.alphaValue = 0.68
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 20),
            imageView.heightAnchor.constraint(equalToConstant: 20),
        ])
        return imageView
    }

    private func cachedIcon(for entry: String) -> NSImage {
        if let image = iconCache[entry] {
            return image.copy() as? NSImage ?? image
        }
        let image = NSWorkspace.shared.icon(forFile: entry)
        iconCache[entry] = image
        return image.copy() as? NSImage ?? image
    }

    private func fallbackIcon(_ appName: String) -> NSView {
        let label = NSTextField(labelWithString: String(appName.prefix(1)).uppercased())
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = NSColor.white.withAlphaComponent(0.58)
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        label.layer?.cornerRadius = 5
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: 20),
            label.heightAnchor.constraint(equalToConstant: 20),
        ])
        return label
    }
}

final class IndicatorApp: NSObject, NSApplicationDelegate {
    private var panelsByScreenName: [String: NSPanel] = [:]
    private var viewsByScreenName: [String: IndicatorView] = [:]
    private var dirtyWatcher: DispatchSourceFileSystemObject?
    private var dirtyFileDescriptor: CInt = -1
    private var queryInFlight = false
    private var queryAgain = false
    private var pendingRefreshWorkItem: DispatchWorkItem?
    private var appEntriesByWorkspaceCache: [String: [String]] = [:]
    private var lastSignature = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        watchDirtyFile()
        refresh()
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        dirtyWatcher?.cancel()
        if dirtyFileDescriptor >= 0 {
            close(dirtyFileDescriptor)
        }
    }

    private func watchDirtyFile() {
        FileManager.default.createFile(atPath: dirtyPath, contents: nil)
        dirtyFileDescriptor = open(dirtyPath, O_EVTONLY)
        guard dirtyFileDescriptor >= 0 else {
            return
        }

        let watcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirtyFileDescriptor,
            eventMask: [.attrib, .extend, .write, .rename, .delete],
            queue: DispatchQueue.main
        )
        watcher.setEventHandler { [weak self] in
            debugLog("dirty event")
            self?.scheduleRefresh()
        }
        watcher.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.dirtyFileDescriptor >= 0 {
                close(self.dirtyFileDescriptor)
                self.dirtyFileDescriptor = -1
            }
        }
        watcher.resume()
        dirtyWatcher = watcher
    }

    private func scheduleRefresh() {
        if queryInFlight {
            queryAgain = true
            return
        }
        if pendingRefreshWorkItem != nil {
            return
        }

        pendingRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.pendingRefreshWorkItem = nil
            self?.refresh()
        }
        pendingRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01, execute: workItem)
    }

    private func refresh() {
        guard !queryInFlight else {
            queryAgain = true
            return
        }

        queryInFlight = true
        let cachedAppEntries = appEntriesByWorkspaceCache
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let workspaceStart = Date()
            let workspaceStates = self?.loadWorkspaceStates(appEntriesByWorkspace: cachedAppEntries) ?? []
            let workspaceElapsedMs = Int(Date().timeIntervalSince(workspaceStart) * 1000)
            DispatchQueue.main.async {
                guard let self else { return }
                debugLog("workspaces loaded \(workspaceStates.count) monitor states in \(workspaceElapsedMs)ms")
                self.apply(states: workspaceStates)
            }

            let windowStart = Date()
            let appEntriesByWorkspace = self?.loadWindowEntries() ?? [:]
            let windowElapsedMs = Int(Date().timeIntervalSince(windowStart) * 1000)
            let states = workspaceStates.map { state in
                MonitorState(
                    monitorName: state.monitorName,
                    workspace: state.workspace,
                    workspaces: state.workspaces,
                    appEntries: appEntriesByWorkspace[state.workspace] ?? state.appEntries
                )
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if !appEntriesByWorkspace.isEmpty {
                    self.appEntriesByWorkspaceCache = appEntriesByWorkspace
                }
                debugLog("windows loaded in \(windowElapsedMs)ms")
                self.queryInFlight = false
                self.apply(states: states)
                if self.queryAgain {
                    self.queryAgain = false
                    self.refresh()
                }
            }
        }
    }

    private func loadWorkspaceStates(appEntriesByWorkspace: [String: [String]]) -> [MonitorState] {
        let workspaceArgs = [
            "list-workspaces",
            "--all",
            "--format",
            "%{monitor-id}%{tab}%{monitor-name}%{tab}%{workspace}%{tab}%{workspace-is-visible}",
        ]
        let workspaceOutput = runAerospace(workspaceArgs)

        var monitorNames: [String] = []
        var visibleWorkspaceByMonitor: [String: String] = [:]
        var workspacesByMonitor: [String: [String]] = [:]

        for line in workspaceOutput.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count == 4 else { continue }
            let monitorName = String(parts[1])
            let workspace = String(parts[2])
            let isVisible = String(parts[3]) == "true"

            if workspacesByMonitor[monitorName] == nil {
                monitorNames.append(monitorName)
                workspacesByMonitor[monitorName] = []
            }
            workspacesByMonitor[monitorName]?.append(workspace)
            if isVisible {
                visibleWorkspaceByMonitor[monitorName] = workspace
            }
        }

        return monitorNames.compactMap { monitorName in
            guard let workspace = visibleWorkspaceByMonitor[monitorName] else {
                return nil
            }
            return MonitorState(
                monitorName: monitorName,
                workspace: workspace,
                workspaces: workspacesByMonitor[monitorName] ?? [],
                appEntries: appEntriesByWorkspace[workspace] ?? []
            )
        }
    }

    private func loadWindowEntries() -> [String: [String]] {
        let windowOutput = runAerospace([
            "list-windows",
            "--all",
            "--format",
            "%{workspace}%{tab}%{app-bundle-path}%{tab}%{app-name}",
        ])

        var appEntriesByWorkspace: [String: [String]] = [:]
        var seenApps = Set<String>()

        for line in windowOutput.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            let workspace = String(parts[0])
            let bundlePath = String(parts[1])
            let appName = String(parts[2])
            let entry = bundlePath.isEmpty ? "name:\(appName)" : bundlePath
            guard !entry.isEmpty else { continue }

            let key = "\(workspace)\t\(entry)"
            guard !seenApps.contains(key) else { continue }
            seenApps.insert(key)
            appEntriesByWorkspace[workspace, default: []].append(entry)
        }

        return appEntriesByWorkspace
    }

    private func runAerospace(_ arguments: [String], timeout: TimeInterval = 1.0) -> String {
        guard FileManager.default.isExecutableFile(atPath: aerospacePath) else {
            return ""
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: aerospacePath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return ""
        }

        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            finished.signal()
        }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return ""
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func apply(states: [MonitorState]) {
        guard !states.isEmpty else {
            return
        }

        let signature = states.map { state in
            "\(state.monitorName)|\(state.workspace)|\(state.workspaces.joined(separator: ","))|\(state.appEntries.joined(separator: ","))"
        }.joined(separator: "\n")
        guard signature != lastSignature || panelsByScreenName.values.contains(where: { !$0.isVisible }) else {
            return
        }
        lastSignature = signature

        let statesByMonitor = Dictionary(uniqueKeysWithValues: states.map { ($0.monitorName, $0) })

        removePanelsForDisconnectedScreens()
        for screen in NSScreen.screens {
            guard let monitorState = statesByMonitor[screen.localizedName] else {
                continue
            }
            let panel = panel(for: screen)
            viewsByScreenName[screen.localizedName]?.update(
                workspace: monitorState.workspace,
                workspaces: monitorState.workspaces,
                appEntries: monitorState.appEntries
            )
            position(
                panel: panel,
                on: screen,
                workspaces: monitorState.workspaces,
                appCount: monitorState.appEntries.count
            )
            panel.orderFrontRegardless()
        }
    }

    private func panel(for screen: NSScreen) -> NSPanel {
        if let panel = panelsByScreenName[screen.localizedName] {
            return panel
        }

        let size = NSSize(width: 190, height: 38)
        let view = IndicatorView(frame: NSRect(origin: .zero, size: size))
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .transient]
        panel.contentView = view

        panelsByScreenName[screen.localizedName] = panel
        viewsByScreenName[screen.localizedName] = view
        return panel
    }

    private func position(panel: NSPanel, on screen: NSScreen, workspaces: [String], appCount: Int) {
        let frame = screen.frame
        let iconCount = min(max(appCount, 0), 8)
        let workspaceWidth = workspaces.reduce(CGFloat(0)) { total, workspace in
            total + CGFloat(workspace.count > 1 ? 30 : 24)
        } + CGFloat(max(workspaces.count - 1, 0) * 5)
        let iconWidth = CGFloat(iconCount * 25)
        let width = 20 + workspaceWidth + (iconCount > 0 ? 10 : 0) + iconWidth
        let size = NSSize(width: max(width, 86), height: 38)
        let margin: CGFloat = 12
        let origin = NSPoint(
            x: frame.minX + margin,
            y: frame.maxY - size.height - margin
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func removePanelsForDisconnectedScreens() {
        let connectedNames = Set(NSScreen.screens.map(\.localizedName))
        for (screenName, panel) in panelsByScreenName where !connectedNames.contains(screenName) {
            panel.close()
            panelsByScreenName.removeValue(forKey: screenName)
            viewsByScreenName.removeValue(forKey: screenName)
        }
    }
}

let app = NSApplication.shared
let delegate = IndicatorApp()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
