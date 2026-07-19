import AppKit
import Dispatch

private let dirtyPath = CommandLine.arguments.dropFirst().first
    ?? "/tmp/aerospace-workspace-indicator-dirty"
private let aerospacePath = "/opt/homebrew/bin/aerospace"
private let reconfigurePath = ProcessInfo.processInfo.environment["AEROSPACE_RECONFIGURE"]
private let debugEnabled = ProcessInfo.processInfo.environment["AEROSPACE_INDICATOR_DEBUG"] == "1"

private func debugLog(_ message: String) {
    guard debugEnabled else { return }
    let timestamp = String(format: "%.3f", Date().timeIntervalSince1970)
    fputs("[workspace-indicator] \(timestamp) \(message)\n", stderr)
}

struct MonitorState {
    // AeroSpace's 1-based, left-to-right monitor sequence number. This is the
    // join key against NSScreen, which is stable even when two displays report
    // the same localized name (e.g. two identical "DELL U2720Q" monitors).
    let monitorID: Int
    let monitorName: String
    let workspace: String
    let workspaces: [String]
    let appEntries: [String]
}

final class WorkspaceChipView: NSView {
    private let workspace: String
    private let selected: Bool

    init(workspace: String, selected: Bool) {
        self.workspace = workspace
        self.selected = selected
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: workspace.count > 1 ? 30 : 24),
            heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if selected {
            NSColor.white.withAlphaComponent(0.16).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: selected ? .semibold : .medium)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(selected ? 0.95 : 0.44),
            .paragraphStyle: paragraph,
        ]
        let attributed = NSAttributedString(string: workspace, attributes: attributes)
        let textSize = attributed.size()
        let textRect = NSRect(
            x: bounds.midX - textSize.width / 2,
            y: bounds.midY - textSize.height / 2 - 0.5,
            width: textSize.width,
            height: textSize.height
        )
        attributed.draw(in: textRect)
    }
}

final class IndicatorView: NSView {
    private let workspaceStack = NSStackView()
    private let iconStack = NSStackView()
    private var iconCache: [String: NSImage] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.16).cgColor
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.07).cgColor

        workspaceStack.orientation = .horizontal
        workspaceStack.alignment = .centerY
        workspaceStack.spacing = 2
        workspaceStack.translatesAutoresizingMaskIntoConstraints = false

        iconStack.orientation = .horizontal
        iconStack.alignment = .centerY
        iconStack.spacing = 2
        iconStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(workspaceStack)
        addSubview(iconStack)

        NSLayoutConstraint.activate([
            workspaceStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            workspaceStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconStack.leadingAnchor.constraint(equalTo: workspaceStack.trailingAnchor, constant: 5),
            iconStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
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
        WorkspaceChipView(workspace: workspace, selected: selected)
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

final class CenterHudView: NSView {
    var workspace = "" {
        didSet {
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.30).cgColor
        layer?.cornerRadius = 20
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let font = NSFont.monospacedDigitSystemFont(ofSize: workspace.count > 1 ? 42 : 46, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.92),
            .paragraphStyle: paragraph,
        ]
        let attributed = NSAttributedString(string: workspace, attributes: attributes)
        let textSize = attributed.size()
        let textRect = NSRect(
            x: bounds.midX - textSize.width / 2,
            y: bounds.midY - textSize.height / 2 - 1,
            width: textSize.width,
            height: textSize.height
        )
        attributed.draw(in: textRect)
    }
}

final class IndicatorApp: NSObject, NSApplicationDelegate {
    // All per-display state is keyed by CGDirectDisplayID. That identifier is
    // unique and stable for the life of a physical display, so it survives two
    // monitors reporting the same localizedName (e.g. two identical DELLs) and
    // the same name later mapping to a different display after a reconnect.
    private var panelsByDisplay: [CGDirectDisplayID: NSPanel] = [:]
    private var viewsByDisplay: [CGDirectDisplayID: IndicatorView] = [:]
    private var centerPanelsByDisplay: [CGDirectDisplayID: NSPanel] = [:]
    private var centerViewsByDisplay: [CGDirectDisplayID: CenterHudView] = [:]
    private var centerHideWorkItemsByDisplay: [CGDirectDisplayID: DispatchWorkItem] = [:]
    private var visibleWorkspaceByDisplay: [CGDirectDisplayID: String] = [:]
    private var lastStatesByDisplay: [CGDirectDisplayID: MonitorState] = [:]
    private var dirtyWatcher: DispatchSourceFileSystemObject?
    private var dirtyFileDescriptor: CInt = -1
    private var queryInFlight = false
    private var queryAgain = false
    private var pendingRefreshWorkItem: DispatchWorkItem?
    private var pendingLayoutWorkItem: DispatchWorkItem?
    private var pendingReconfigureWorkItem: DispatchWorkItem?
    private var reconfigureProcess: Process?
    private var appEntriesByWorkspaceCache: [String: [String]] = [:]
    private var lastSignature = ""
    private var lastScreenLayoutSignature = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        lastScreenLayoutSignature = screenLayoutSignature()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screenParametersChanged(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screenParametersChanged(_:)),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        watchDirtyFile()
        refresh()
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkScreenLayout()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        dirtyWatcher?.cancel()
        if dirtyFileDescriptor >= 0 {
            close(dirtyFileDescriptor)
            dirtyFileDescriptor = -1
        }
    }

    @objc private func screenParametersChanged(_ notification: Notification) {
        scheduleLayoutChange()
    }

    private func checkScreenLayout() {
        if screenLayoutSignature() != lastScreenLayoutSignature {
            scheduleLayoutChange()
        }
    }

    // Wake and dock/undock events arrive as a burst of screen-parameter
    // notifications while the displays re-enumerate one at a time. Coalesce them
    // so the panels are rebuilt once, after the layout settles, instead of
    // thrashing (and tearing down panels for displays that are only transiently
    // absent) on every intermediate notification.
    private func scheduleLayoutChange() {
        pendingLayoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.pendingLayoutWorkItem = nil
            self?.handleScreenLayoutChanged()
        }
        pendingLayoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    private func handleScreenLayoutChanged() {
        let signature = screenLayoutSignature()
        let changed = signature != lastScreenLayoutSignature
        lastScreenLayoutSignature = signature
        lastSignature = ""
        repositionPanelsFromCachedStates()
        if changed {
            triggerReconfigure()
        }
        refresh()
    }

    // AeroSpace does not re-apply workspace-to-monitor-force-assignment when a
    // monitor reconnects (upstream issue #520). The nix-darwin launchd agent
    // passes a helper via AEROSPACE_RECONFIGURE that re-renders the config for
    // the current displays and issues reload-config. Debounce it so a single
    // settled layout change triggers exactly one re-home.
    private func triggerReconfigure() {
        guard let reconfigurePath, !reconfigurePath.isEmpty else { return }
        pendingReconfigureWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: reconfigurePath)
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            // Retain the process until it exits and reap it via the termination
            // handler so it never lingers as a zombie.
            process.terminationHandler = { _ in
                DispatchQueue.main.async { self?.reconfigureProcess = nil }
            }
            do {
                try process.run()
                DispatchQueue.main.async { self?.reconfigureProcess = process }
            } catch {
                debugLog("reconfigure failed to launch: \(error)")
            }
        }
        pendingReconfigureWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func watchDirtyFile() {
        dirtyWatcher?.cancel()
        if dirtyFileDescriptor >= 0 {
            close(dirtyFileDescriptor)
            dirtyFileDescriptor = -1
        }

        FileManager.default.createFile(atPath: dirtyPath, contents: nil)
        dirtyFileDescriptor = open(dirtyPath, O_EVTONLY)
        guard dirtyFileDescriptor >= 0 else {
            // The file could not be opened; try again shortly rather than going
            // permanently deaf to workspace-change events.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.watchDirtyFile()
            }
            return
        }

        let watcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirtyFileDescriptor,
            eventMask: [.attrib, .extend, .write, .rename, .delete],
            queue: DispatchQueue.main
        )
        watcher.setEventHandler { [weak self] in
            guard let self else { return }
            let events = watcher.data
            debugLog("dirty event \(events.rawValue)")
            // If the file is replaced or removed the file descriptor still
            // points at the old inode, so re-establish the watch on the new
            // path. Otherwise just refresh.
            if events.contains(.delete) || events.contains(.rename) {
                self.watchDirtyFile()
            }
            self.scheduleRefresh()
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
            let workspaceStates = self?.loadWorkspaceStates(appEntriesByWorkspace: cachedAppEntries)
            let workspaceElapsedMs = Int(Date().timeIntervalSince(workspaceStart) * 1000)
            DispatchQueue.main.async {
                guard let self else { return }
                debugLog("workspaces loaded \(workspaceStates?.count.description ?? "nil") monitor states in \(workspaceElapsedMs)ms")
                self.apply(states: workspaceStates)
            }

            let windowStart = Date()
            let appEntriesByWorkspace = self?.loadWindowEntries() ?? [:]
            let windowElapsedMs = Int(Date().timeIntervalSince(windowStart) * 1000)
            let states: [MonitorState]? = workspaceStates.map { loaded in
                loaded.map { state in
                    MonitorState(
                        monitorID: state.monitorID,
                        monitorName: state.monitorName,
                        workspace: state.workspace,
                        workspaces: state.workspaces,
                        appEntries: appEntriesByWorkspace[state.workspace] ?? state.appEntries
                    )
                }
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

    // Returns nil when the AeroSpace query fails (not running yet, timed out).
    // Callers must treat nil differently from an empty result so a transient
    // failure on wake does not blank the indicator.
    private func loadWorkspaceStates(appEntriesByWorkspace: [String: [String]]) -> [MonitorState]? {
        let workspaceArgs = [
            "list-workspaces",
            "--all",
            "--format",
            "%{monitor-id}%{tab}%{monitor-name}%{tab}%{workspace}%{tab}%{workspace-is-visible}",
        ]
        guard let workspaceOutput = runAerospace(workspaceArgs) else {
            return nil
        }

        var monitorOrder: [Int] = []
        var namesByMonitor: [Int: String] = [:]
        var visibleWorkspaceByMonitor: [Int: String] = [:]
        var workspacesByMonitor: [Int: [String]] = [:]

        for line in workspaceOutput.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count == 4, let monitorID = Int(parts[0]) else { continue }
            let monitorName = String(parts[1])
            let workspace = String(parts[2])
            let isVisible = String(parts[3]) == "true"

            if workspacesByMonitor[monitorID] == nil {
                monitorOrder.append(monitorID)
                workspacesByMonitor[monitorID] = []
                namesByMonitor[monitorID] = monitorName
            }
            workspacesByMonitor[monitorID]?.append(workspace)
            if isVisible {
                visibleWorkspaceByMonitor[monitorID] = workspace
            }
        }

        return monitorOrder.compactMap { monitorID in
            guard let workspace = visibleWorkspaceByMonitor[monitorID] else {
                return nil
            }
            return MonitorState(
                monitorID: monitorID,
                monitorName: namesByMonitor[monitorID] ?? "",
                workspace: workspace,
                workspaces: workspacesByMonitor[monitorID] ?? [],
                appEntries: appEntriesByWorkspace[workspace] ?? []
            )
        }
    }

    private func loadWindowEntries() -> [String: [String]] {
        guard let windowOutput = runAerospace([
            "list-windows",
            "--all",
            "--format",
            "%{workspace}%{tab}%{app-bundle-path}%{tab}%{app-name}",
        ]) else {
            return [:]
        }

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

    // Returns nil when the command could not be run to completion (binary
    // missing, launch error, or timeout). An empty String means the command
    // succeeded with no output.
    //
    // IMPORTANT: completion is observed via `terminationHandler`, NOT a
    // `waitUntilExit()` call parked on a background thread. A parked
    // waitUntilExit leaks one thread per timed-out call (aerospace can take
    // >timeout right after wake or when the WM is busy); over days those
    // threads saturate the dispatch pool and the indicator silently freezes.
    // On timeout the child is escalated SIGTERM -> SIGKILL so it cannot linger.
    private func runAerospace(_ arguments: [String], timeout: TimeInterval = 1.0) -> String? {
        guard FileManager.default.isExecutableFile(atPath: aerospacePath) else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: aerospacePath)
        process.arguments = arguments

        let outPipe = Pipe()
        process.standardOutput = outPipe
        // Discard stderr via /dev/null so there is no second pipe to drain.
        process.standardError = FileHandle.nullDevice

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }

        var timedOut = false
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if exited.wait(timeout: .now() + 0.3) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 0.5)
            }
            timedOut = true
        }

        // The child has exited (or been killed), so its write end of the pipe
        // is closed and this read returns immediately at EOF. Output for the
        // list-* commands is well under the pipe buffer, so a synchronous read
        // after exit cannot deadlock -- and there is no background reader thread
        // that could leak.
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        return timedOut ? nil : (String(data: data, encoding: .utf8) ?? "")
    }

    private func apply(states: [MonitorState]?) {
        // nil = query failed (aerospace not ready). Keep whatever is on screen
        // rather than tearing panels down. An empty array is the same: never
        // blank the display on a transient hiccup.
        guard let states, !states.isEmpty else {
            return
        }

        let stateSignature = states.map { state in
            "\(state.monitorID)|\(state.monitorName)|\(state.workspace)|\(state.workspaces.joined(separator: ","))|\(state.appEntries.joined(separator: ","))"
        }.joined(separator: "\n")
        let layoutSignature = screenLayoutSignature()
        let signature = "\(stateSignature)\n\(layoutSignature)"
        guard signature != lastSignature || panelsByDisplay.values.contains(where: { !$0.isVisible }) else {
            return
        }
        lastSignature = signature
        lastScreenLayoutSignature = layoutSignature

        let resolved = resolveStatesToScreens(states)
        lastStatesByDisplay = resolved.reduce(into: [:]) { acc, pair in
            acc[displayID(of: pair.screen)] = pair.state
        }

        removePanelsForDisconnectedScreens()
        for (screen, monitorState) in resolved {
            let display = displayID(of: screen)
            if let previousWorkspace = visibleWorkspaceByDisplay[display],
               previousWorkspace != monitorState.workspace {
                showCenterHud(workspace: monitorState.workspace, on: screen)
            }
            visibleWorkspaceByDisplay[display] = monitorState.workspace

            let panel = panel(for: screen)
            viewsByDisplay[display]?.update(
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

    private func repositionPanelsFromCachedStates() {
        guard !lastStatesByDisplay.isEmpty else {
            return
        }

        removePanelsForDisconnectedScreens()
        for screen in NSScreen.screens {
            guard let monitorState = lastStatesByDisplay[displayID(of: screen)] else {
                continue
            }
            let panel = panel(for: screen)
            viewsByDisplay[displayID(of: screen)]?.update(
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

    // Match AeroSpace monitor states to the physical NSScreens. AeroSpace names
    // usually equal NSScreen.localizedName, so match by name first. When a name
    // is ambiguous (two identical monitors) or absent, fall back to AeroSpace's
    // 1-based left-to-right monitor-id, which lines up with the screens sorted
    // by origin.
    private func resolveStatesToScreens(_ states: [MonitorState]) -> [(screen: NSScreen, state: MonitorState)] {
        var statesByName: [String: [MonitorState]] = [:]
        var statesBySeq: [Int: MonitorState] = [:]
        for state in states {
            statesByName[state.monitorName, default: []].append(state)
            statesBySeq[state.monitorID] = state
        }

        let orderedScreens = NSScreen.screens.sorted { lhs, rhs in
            if lhs.frame.minX != rhs.frame.minX {
                return lhs.frame.minX < rhs.frame.minX
            }
            return lhs.frame.minY < rhs.frame.minY
        }

        var result: [(screen: NSScreen, state: MonitorState)] = []
        var usedMonitorIDs = Set<Int>()
        for (index, screen) in orderedScreens.enumerated() {
            let seq = index + 1
            var match: MonitorState?
            if let byName = statesByName[screen.localizedName], byName.count == 1 {
                match = byName.first
            } else if let byName = statesByName[screen.localizedName], byName.count > 1 {
                // Duplicate names: disambiguate by sequence number.
                match = byName.first { $0.monitorID == seq } ?? statesBySeq[seq]
            } else {
                match = statesBySeq[seq]
            }
            guard let state = match, !usedMonitorIDs.contains(state.monitorID) else {
                continue
            }
            usedMonitorIDs.insert(state.monitorID)
            result.append((screen, state))
        }
        return result
    }

    private func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    private func screenLayoutSignature() -> String {
        NSScreen.screens.map { screen in
            let frame = screen.frame
            return "\(displayID(of: screen))|\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width)),\(Int(frame.height))"
        }
        .sorted()
        .joined(separator: "\n")
    }

    private func panel(for screen: NSScreen) -> NSPanel {
        let display = displayID(of: screen)
        if let panel = panelsByDisplay[display] {
            return panel
        }

        let size = NSSize(width: 170, height: 32)
        let view = IndicatorView(frame: NSRect(origin: .zero, size: size))
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // NSPanel defaults to isReleasedWhenClosed = true, which combined with
        // the strong reference held here would over-release the panel when we
        // tear it down on disconnect. Keep ownership with ARC.
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .transient]
        panel.contentView = view

        panelsByDisplay[display] = panel
        viewsByDisplay[display] = view
        return panel
    }

    private func position(panel: NSPanel, on screen: NSScreen, workspaces: [String], appCount: Int) {
        let frame = screen.frame
        let iconCount = min(max(appCount, 0), 8)
        let workspaceWidth = workspaces.reduce(CGFloat(0)) { total, workspace in
            total + CGFloat(workspace.count > 1 ? 30 : 24)
        } + CGFloat(max(workspaces.count - 1, 0) * 2)
        let iconWidth = CGFloat(iconCount * 20 + max(iconCount - 1, 0) * 2)
        let width = 12 + workspaceWidth + (iconCount > 0 ? 5 : 0) + iconWidth
        let size = NSSize(width: max(width, 76), height: 32)
        let margin: CGFloat = 12
        let origin = NSPoint(
            x: frame.minX + margin,
            y: frame.maxY - size.height - margin
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func showCenterHud(workspace: String, on screen: NSScreen) {
        let display = displayID(of: screen)
        let panel = centerPanel(for: screen)
        centerViewsByDisplay[display]?.workspace = workspace
        positionCenter(panel: panel, on: screen, workspace: workspace)

        centerHideWorkItemsByDisplay[display]?.cancel()
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        let hideWorkItem = DispatchWorkItem { [weak panel] in
            guard let panel else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
            })
        }
        centerHideWorkItemsByDisplay[display] = hideWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.58, execute: hideWorkItem)
    }

    private func centerPanel(for screen: NSScreen) -> NSPanel {
        let display = displayID(of: screen)
        if let panel = centerPanelsByDisplay[display] {
            return panel
        }

        let size = NSSize(width: 92, height: 76)
        let view = CenterHudView(frame: NSRect(origin: .zero, size: size))
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .transient]
        panel.contentView = view

        centerPanelsByDisplay[display] = panel
        centerViewsByDisplay[display] = view
        return panel
    }

    private func positionCenter(panel: NSPanel, on screen: NSScreen, workspace: String) {
        let frame = screen.frame
        let size = NSSize(width: workspace.count > 1 ? 102 : 86, height: 74)
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func removePanelsForDisconnectedScreens() {
        let connected = Set(NSScreen.screens.map { displayID(of: $0) })
        for (display, panel) in panelsByDisplay where !connected.contains(display) {
            panel.orderOut(nil)
            panelsByDisplay.removeValue(forKey: display)
            viewsByDisplay.removeValue(forKey: display)
            visibleWorkspaceByDisplay.removeValue(forKey: display)
        }
        for (display, panel) in centerPanelsByDisplay where !connected.contains(display) {
            centerHideWorkItemsByDisplay[display]?.cancel()
            panel.orderOut(nil)
            centerPanelsByDisplay.removeValue(forKey: display)
            centerViewsByDisplay.removeValue(forKey: display)
            centerHideWorkItemsByDisplay.removeValue(forKey: display)
        }
    }
}

let app = NSApplication.shared
let delegate = IndicatorApp()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
