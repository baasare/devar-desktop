import SwiftUI
import Foundation
import Observation
import ServiceManagement
import AppKit

@MainActor
enum BrandAssets {
    static let menuBarMark: NSImage = {
        guard let url = Bundle.module.url(forResource: "devar-logo-mark", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "quote.bubble", accessibilityDescription: "Devar")!
        }
        image.size = NSSize(width: 14, height: 14)
        image.isTemplate = true
        return image
    }()
}

@main
struct DevarDesktopApp: App {
    @State private var session: DesktopSession
    @State private var menuBarController: DevarMenuBarController

    @MainActor
    init() {
        let session = DesktopSession()
        let controller = DevarMenuBarController(session: session)
        session.menuBarController = controller
        _session = State(initialValue: session)
        _menuBarController = State(initialValue: controller)
        controller.refresh()
    }

    var body: some Scene {
        Settings {
            SettingsView(session: session)
                .frame(minWidth: 650, minHeight: 480)
        }
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit Devar") { session.shutdown() ; NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
    }
}

@MainActor
private final class DevarMenuBarController: NSObject, NSPopoverDelegate {
    private let session: DesktopSession
    private let statusItem: NSStatusItem
    private var controlsPanel: LiveListeningControlsPopover!
    private var settingsWindow: NSWindow?
    private var outsideClickMonitor: Any?
    private lazy var popover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 360, height: 560)
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: DevarPopover(session: session) { [weak self] in
            self?.openSettings()
        })
        return popover
    }()

    init(session: DesktopSession) {
        self.session = session
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        controlsPanel = LiveListeningControlsPopover(session: session, statusItem: statusItem)
        if let button = statusItem.button {
            button.image = BrandAssets.menuBarMark
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.toolTip = "Devar scripture suggestions"
            button.setAccessibilityLabel("Devar scripture suggestions")
        }
    }

    func refresh() {
        if let button = statusItem.button {
            let title = NSMutableAttributedString()
            if session.state == .listening {
                title.append(NSAttributedString(string: "● ", attributes: [
                    .foregroundColor: NSColor.systemRed,
                    .font: NSFont.systemFont(ofSize: 9, weight: .bold)
                ]))
            }
            if let reference = session.currentSuggestion?.reference {
                title.append(NSAttributedString(string: reference, attributes: [
                    .foregroundColor: NSColor.labelColor,
                    .font: NSFont.systemFont(ofSize: 13, weight: .medium)
                ]))
            }
            button.attributedTitle = title
            button.toolTip = session.currentSuggestion?.reference ?? "Devar scripture suggestions"
        }
        controlsPanel?.update(for: session)
    }

    @objc private func togglePopover(_ sender: Any?) {
        session.copyCurrentVerseReference()
        controlsPanel.hideForMainPopover()
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            monitorForOutsideClicks()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        stopMonitoringOutsideClicks()
    }

    private func monitorForOutsideClicks() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closePopoverIfClickWasOutside()
            }
        }
    }

    private func closePopoverIfClickWasOutside() {
        guard popover.isShown else {
            stopMonitoringOutsideClicks()
            return
        }

        let clickLocation = NSEvent.mouseLocation
        if let panelFrame = popover.contentViewController?.view.window?.frame,
           panelFrame.contains(clickLocation) {
            return
        }

        if let button = statusItem.button,
           let window = button.window,
           window.convertToScreen(button.convert(button.bounds, to: nil)).contains(clickLocation) {
            return
        }

        popover.performClose(nil)
    }

    private func stopMonitoringOutsideClicks() {
        guard let outsideClickMonitor else { return }
        NSEvent.removeMonitor(outsideClickMonitor)
        self.outsideClickMonitor = nil
    }

    private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Devar Settings"
            window.contentViewController = NSHostingController(rootView: SettingsView(session: session)
                .frame(minWidth: 650, minHeight: 480))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private final class LiveListeningControlsPopover {
    private weak var session: DesktopSession?
    private let statusItem: NSStatusItem
    private var popover: NSPopover?
    private var minimizedForCurrentListeningSession = false

    init(session: DesktopSession, statusItem: NSStatusItem) {
        self.session = session
        self.statusItem = statusItem
    }

    func update(for session: DesktopSession) {
        self.session = session
        guard session.state == .listening else {
            if popover?.isShown == true { popover?.close() }
            minimizedForCurrentListeningSession = false
            return
        }
        guard !minimizedForCurrentListeningSession else { return }

        guard let button = statusItem.button else { return }
        if popover == nil {
            let popover = NSPopover()
            popover.behavior = .applicationDefined
            popover.animates = false
            popover.contentSize = NSSize(width: 148, height: 44)
            popover.contentViewController = NSHostingController(rootView: LiveListeningControls(session: session) {
                self.minimize()
            })
            self.popover = popover
        }

        guard let popover, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func minimize() {
        minimizedForCurrentListeningSession = true
        if popover?.isShown == true { popover?.close() }
    }

    func hideForMainPopover() {
        if popover?.isShown == true { popover?.close() }
    }
}

private struct LiveListeningControls: View {
    @Bindable var session: DesktopSession
    let minimize: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button { session.copyCurrentVerseReference() } label: {
                Image(systemName: "doc.on.doc")
                    .frame(width: 32, height: 30)
                    .foregroundStyle(session.currentSuggestion == nil ? Color.secondary.opacity(0.45) : Color.primary)
            }
            .buttonStyle(.plain)
            .disabled(session.currentSuggestion == nil)
            .help("Copy verse reference")
            .accessibilityLabel("Copy verse reference")

            Button { session.isPinned.toggle() } label: {
                Image(systemName: session.isPinned ? "pin.fill" : "pin")
                    .frame(width: 32, height: 30)
                    .foregroundStyle(session.isPinned ? Color.accentColor : Color.primary)
            }
            .buttonStyle(.plain)
            .help(session.isPinned ? "Unpin current verse" : "Pin current verse")
            .accessibilityLabel(session.isPinned ? "Unpin current verse" : "Pin current verse")

            Button { session.stop() } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 32, height: 30)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Stop listening")
            .accessibilityLabel("Stop listening")

            Button(action: minimize) {
                Image(systemName: "minus")
                    .frame(width: 32, height: 30)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Hide compact controls until the next listening session")
            .accessibilityLabel("Minimize compact controls")
        }
        .frame(width: 140, height: 38)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.55), lineWidth: 1))
        .padding(2)
    }
}

private struct StartListeningButtonStyle: ButtonStyle {
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.white : Color.primary.opacity(0.78))
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(
                isEnabled ? Color.accentColor.opacity(configuration.isPressed ? 0.78 : 1) : Color.primary.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isEnabled ? Color.clear : Color.primary.opacity(0.12), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct AudioDevice: Identifiable, Hashable {
    let id: Int
    let name: String
    let channels: Int
}

struct VerseSuggestion: Identifiable {
    let id = UUID()
    let reference: String
    let translation: String
    let text: String
}

@MainActor
@Observable
final class DesktopSession {
    enum ListeningState: Equatable {
        case starting, loadingData, loadingModel, listening, paused, stopped, failed

        var label: String {
            switch self {
            case .starting: "Connecting"
            case .loadingData: "Preparing local Bible data"
            case .loadingModel: "Preparing speech model"
            case .listening: "Listening"
            case .paused: "Paused"
            case .stopped: "Stopped"
            case .failed: "Needs attention"
            }
        }
    }

    var state: ListeningState = .starting {
        didSet { menuBarController?.refresh() }
    }
    var devices: [AudioDevice] = []
    var selectedDeviceID: Int? {
        didSet {
            if let name = selectedDevice?.name {
                UserDefaults.standard.set(name, forKey: "selectedAudioDeviceName")
                restoredDeviceName = name
            }
        }
    }
    var translation = UserDefaults.standard.string(forKey: "desktopTranslation") ?? "NKJV" {
        didSet { UserDefaults.standard.set(translation, forKey: "desktopTranslation") }
    }
    var bibleDirectory = UserDefaults.standard.string(forKey: "bibleDirectory") ?? ""
    var suggestionCount = UserDefaults.standard.integer(forKey: "desktopSuggestionCount") {
        didSet { UserDefaults.standard.set(suggestionCount, forKey: "desktopSuggestionCount") }
    }
    var refreshSeconds = UserDefaults.standard.integer(forKey: "desktopRefreshSeconds") {
        didSet { UserDefaults.standard.set(refreshSeconds, forKey: "desktopRefreshSeconds") }
    }
    var contextSeconds = UserDefaults.standard.integer(forKey: "desktopContextSeconds") {
        didSet { UserDefaults.standard.set(contextSeconds, forKey: "desktopContextSeconds") }
    }
    var transcript = ""
    var errorMessage: String?
    var modelProgress: Double?
    var semanticProgress: Double?
    var modelReady = false
    var engineName = "On-device transcription"
    var semanticSearchPreparing = false
    var isPinned = false
    var currentSuggestion: VerseSuggestion? {
        didSet { menuBarController?.refresh() }
    }
    var alternatives: [VerseSuggestion] = []
    var launchAtLogin: Bool = UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool ?? true {
        didSet { updateLaunchAtLogin() }
    }

    @ObservationIgnored private var bridge: LocalBridge?
    @ObservationIgnored fileprivate weak var menuBarController: DevarMenuBarController?
    @ObservationIgnored private var restoredDeviceName = UserDefaults.standard.string(forKey: "selectedAudioDeviceName")

    init() {
        if UserDefaults.standard.object(forKey: "launchAtLogin") == nil {
            UserDefaults.standard.set(true, forKey: "launchAtLogin")
            do { try SMAppService.mainApp.register() }
            catch { errorMessage = "Could not enable launch at login: \(error.localizedDescription)" }
        }
        let bridge = LocalBridge()
        self.bridge = bridge
        if suggestionCount == 0 { suggestionCount = 3 }
        if refreshSeconds == 0 { refreshSeconds = 3 }
        if contextSeconds == 0 { contextSeconds = 30 }
        bridge.onEvent = { [weak self] event in self?.receive(event) }
        do {
            try bridge.start()
            bridge.send(["action": "prepare", "translation": translation])
        } catch {
            state = .failed
            errorMessage = error.localizedDescription
        }
    }

    var selectedDevice: AudioDevice? {
        devices.first(where: { $0.id == selectedDeviceID })
    }

    var inputLabel: String { selectedDevice?.name ?? "Choose an audio input" }

    func refreshDevices() {
        bridge?.send(["action": "refresh-devices"])
    }

    func start() {
        guard modelReady else {
            errorMessage = nil
            state = .loadingData
            bridge?.send(["action": "prepare", "translation": translation])
            return
        }
        guard let selectedDeviceID else {
            errorMessage = "Choose an audio input before starting."
            return
        }
        errorMessage = nil
        state = .starting
        modelProgress = nil
        transcript = ""
        bridge?.send([
            "action": "start", "deviceId": selectedDeviceID, "translation": translation,
            "suggestionCount": suggestionCount, "refreshSeconds": refreshSeconds,
            "contextSeconds": contextSeconds,
        ])
    }

    func toggleListening() {
        switch state {
        case .listening:
            bridge?.send(["action": "pause"])
            state = .paused
        case .paused, .stopped, .failed:
            start()
        case .starting, .loadingData, .loadingModel:
            break
        }
    }

    func stop() {
        bridge?.send(["action": "stop"])
        state = .stopped
        transcript = ""
        currentSuggestion = nil
        alternatives = []
        modelProgress = nil
    }

    func chooseBibleDirectory() {
        guard state != .listening, state != .paused else {
            errorMessage = "Stop listening before changing the Bible data folder."
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Choose Bible Data Folder"
        panel.message = "Choose a folder containing licensed Bible JSON files, such as nkjv.json."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        bibleDirectory = url.path
        UserDefaults.standard.set(bibleDirectory, forKey: "bibleDirectory")
        modelReady = false
        errorMessage = nil
        state = .loadingData
        bridge?.send(["action": "set-bible-directory", "path": bibleDirectory, "translation": translation])
    }

    func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    func copyCurrentVerseReference() {
        guard let currentSuggestion else { return }
        copy(currentSuggestion.reference)
    }

    func shutdown() { bridge?.shutdown() }

    private func updateLaunchAtLogin() {
        UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = "Could not update launch at login: \(error.localizedDescription)"
        }
    }

    private func receive(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "ready", "devices":
            if let engine = event["engine"] as? String { engineName = engine }
            if let items = event["devices"] as? [[String: Any]] {
                devices = items.compactMap { item in
                    guard let id = item["id"] as? Int, let name = item["name"] as? String else { return nil }
                    return AudioDevice(id: id, name: name, channels: item["channels"] as? Int ?? 1)
                }
                if selectedDeviceID == nil, let first = devices.first {
                    if let restoredDeviceName,
                       let matching = devices.first(where: { $0.name == restoredDeviceName }) {
                        selectedDeviceID = matching.id
                    } else if restoredDeviceName == nil {
                        selectedDeviceID = first.id
                    }
                } else if let selectedDeviceID,
                          !devices.contains(where: { $0.id == selectedDeviceID }) {
                    // A missing saved device must not silently switch to another microphone.
                    self.selectedDeviceID = nil
                }
            }
        case "state":
            switch event["state"] as? String {
            case "loading-data": state = .loadingData
            case "loading-model": state = .loadingModel
            case "prepared":
                modelReady = true
                state = .stopped
            case "connecting": state = .starting
            case "listening": state = .listening
            case "paused": state = .paused
            case "stopped": state = .stopped
            case "error": state = .failed
            default: break
            }
        case "engine":
            engineName = event["name"] as? String ?? engineName
        case "progress":
            if event["item"] as? String == "Preparing verses" {
                semanticProgress = event["fraction"] as? Double
            } else {
                modelProgress = event["fraction"] as? Double
            }
        case "semantic-search":
            semanticSearchPreparing = event["preparing"] as? Bool ?? false
            if !semanticSearchPreparing { semanticProgress = nil }
        case "semantic-index-ready":
            semanticSearchPreparing = false
            semanticProgress = nil
        case "transcript":
            transcript = event["text"] as? String ?? ""
        case "suggestions":
            let items = (event["suggestions"] as? [[String: Any]] ?? []).compactMap { item -> VerseSuggestion? in
                guard let reference = item["reference"] as? String,
                      let text = item["text"] as? String else { return nil }
                return VerseSuggestion(reference: reference, translation: item["translation"] as? String ?? translation, text: text)
            }
            if !isPinned || currentSuggestion == nil { currentSuggestion = items.first }
            alternatives = Array(items.dropFirst())
        case "error":
            errorMessage = event["message"] as? String ?? "The local audio service reported an error."
            if state == .loadingModel || state == .loadingData || state == .listening || state == .starting { state = .failed }
        case "notice":
            errorMessage = event["message"] as? String
        default:
            break
        }
    }
}

@MainActor
private final class LocalBridge {
    var onEvent: (([String: Any]) -> Void)?
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()

    func start() throws {
        let resources = Bundle.main.resourceURL
        let packagedHelper = resources?.appendingPathComponent("DevarSpeech/DevarSpeech")
        let isPackaged = packagedHelper.map { FileManager.default.isExecutableFile(atPath: $0.path) } ?? false
        let sourceFile = URL(fileURLWithPath: #filePath)
        let projectRoot = sourceFile.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        if isPackaged, let packagedHelper {
            process.executableURL = packagedHelper
            process.arguments = []
            process.currentDirectoryURL = resources
        } else {
            let python = projectRoot.appendingPathComponent(".venv/bin/python")
            guard FileManager.default.isExecutableFile(atPath: python.path) else {
                throw NSError(domain: "DevarDesktop", code: 1, userInfo: [NSLocalizedDescriptionKey: "The local speech helper is missing. Rebuild the development app or reinstall the Devar test package."])
            }
            guard let helper = Bundle.module.url(forResource: "desktop_bridge", withExtension: "py") else {
                throw NSError(domain: "DevarDesktop", code: 2, userInfo: [NSLocalizedDescriptionKey: "The local audio helper could not be found in the app resources."])
            }
            process.executableURL = python
            process.arguments = [helper.path]
            process.currentDirectoryURL = projectRoot
        }
        var environment = ProcessInfo.processInfo.environment
        if isPackaged, let resources {
            let bundledBibleDirectory = resources.appendingPathComponent("Bibles", isDirectory: true).path
            if FileManager.default.fileExists(atPath: bundledBibleDirectory) {
                environment["DEVAR_BIBLE_DIR"] = bundledBibleDirectory
            }
            if let packagedHelper {
                let helperDirectory = packagedHelper.deletingLastPathComponent()
                let bundledLibraries = [
                    helperDirectory.appendingPathComponent("_internal", isDirectory: true).path,
                    helperDirectory.path,
                ]
                let existingLibraries = environment["DYLD_LIBRARY_PATH"].map { [$0] } ?? []
                environment["DYLD_LIBRARY_PATH"] = (bundledLibraries + existingLibraries).joined(separator: ":")
            }
        } else {
            environment["DEVAR_REPO_ROOT"] = projectRoot.deletingLastPathComponent().deletingLastPathComponent().path
        }
        if let savedBibleDirectory = UserDefaults.standard.string(forKey: "bibleDirectory"),
           !savedBibleDirectory.isEmpty {
            environment["DEVAR_BIBLE_DIR"] = savedBibleDirectory
        }
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.standardError
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in self?.consume(data) }
        }
        try process.run()
        process.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                guard process.terminationStatus != 0 else { return }
                self?.onEvent?(["type": "error", "message": "The local audio helper exited unexpectedly."])
            }
        }
    }

    func send(_ value: [String: Any]) {
        guard process.isRunning, let data = try? JSONSerialization.data(withJSONObject: value) else { return }
        input.fileHandleForWriting.write(data)
        input.fileHandleForWriting.write(Data([0x0A]))
    }

    func shutdown() {
        send(["action": "quit"])
        if process.isRunning { process.waitUntilExit() }
        output.fileHandleForReading.readabilityHandler = nil
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstRange(of: Data([0x0A])) {
            let line = buffer.subdata(in: buffer.startIndex..<newline.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<newline.upperBound)
            guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            onEvent?(event)
        }
    }
}

private struct DevarPopover: View {
    @Bindable var session: DesktopSession
    let openSettings: () -> Void
    @State private var isExpanded = false

    private var isListening: Bool { session.state == .listening }
    private var panelWidth: CGFloat { isExpanded ? 440 : 360 }
    private var panelHeight: CGFloat { isExpanded ? 720 : 560 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            statusNotice
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    transcriptPreview
                    suggestions
                }
            }
            .scrollIndicators(.visible)
            listeningControls
            footer
        }
        .frame(width: panelWidth, height: panelHeight)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.snappy(duration: 0.22), value: isExpanded)
        .onAppear { session.copyCurrentVerseReference() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: BrandAssets.menuBarMark)
                .resizable()
                .scaledToFit()
                .frame(width: isExpanded ? 28 : 24, height: isExpanded ? 28 : 24)
                .padding(isExpanded ? 7 : 5)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text("Devar").font(.system(size: 14, weight: .semibold))
                Label("\(session.state.label) · \(session.inputLabel)", systemImage: isListening ? "waveform" : "pause.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(isListening ? .green : .secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button { isExpanded.toggle() } label: {
                Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Make panel smaller" : "Expand panel")
            .accessibilityLabel(isExpanded ? "Make panel smaller" : "Expand panel")
        }
        .padding(.horizontal, isExpanded ? 20 : 15)
        .padding(.top, isExpanded ? 18 : 12)
        .padding(.bottom, isExpanded ? 14 : 8)
    }

    @ViewBuilder
    private var statusNotice: some View {
        if let error = session.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, isExpanded ? 20 : 15)
                .padding(.bottom, 8)
        } else if session.state == .loadingData || session.state == .loadingModel {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(session.state == .loadingData ? "Preparing Bible data…" : "Preparing speech model…")
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 4)
                if session.state == .loadingModel, let progress = session.modelProgress {
                    ProgressView(value: progress).frame(width: 58)
                }
            }
            .padding(.horizontal, isExpanded ? 20 : 15)
            .padding(.bottom, 8)
        } else if session.semanticSearchPreparing {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Preparing verse matches…")
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 4)
                if let progress = session.semanticProgress {
                    ProgressView(value: progress).frame(width: 58)
                }
            }
            .padding(.horizontal, isExpanded ? 20 : 15)
            .padding(.bottom, 8)
        }
    }

    private var transcriptPreview: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("LIVE TRANSCRIPT")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(.secondary)
            Text(session.transcript.isEmpty ? "Your live transcript will appear here." : twoLineTranscript(session.transcript))
                .font(.system(size: isExpanded ? 14 : 12))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(session.transcript.isEmpty ? Color.secondary.opacity(0.75) : Color.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, isExpanded ? 20 : 15)
        .padding(.top, isExpanded ? 2 : 0)
        .padding(.bottom, isExpanded ? 10 : 8)
    }

    private func twoLineTranscript(_ text: String) -> String {
        var lines: [String] = []
        var currentLine = ""
        for word in text.split(whereSeparator: \.isWhitespace).map(String.init) {
            if currentLine.isEmpty {
                currentLine = word
            } else if currentLine.count + word.count + 1 <= 44 {
                currentLine += " \(word)"
            } else {
                lines.append(currentLine)
                currentLine = word
            }
        }
        if !currentLine.isEmpty { lines.append(currentLine) }
        return lines.suffix(2).joined(separator: "\n")
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 13 : 8) {
            if let suggestion = session.currentSuggestion {
                verseCard(suggestion)
            } else {
                ContentUnavailableView("No passage yet", systemImage: "text.magnifyingglass", description: Text("Scripture matches will appear here."))
                    .frame(maxWidth: .infinity, minHeight: isExpanded ? 300 : 150)
            }
            if !session.alternatives.isEmpty {
                Text("OTHER POSSIBILITIES")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.1).foregroundStyle(.secondary).padding(.top, 3)
                ForEach(session.alternatives) { alternative in
                    HStack(spacing: 8) {
                        Text(alternative.reference).font(.system(size: 13, weight: .semibold)).frame(width: 100, alignment: .leading)
                        Text(alternative.text).font(.system(size: 13, design: .serif)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                        Button("Copy") { session.copy(alternative.reference) }
                            .font(.system(size: 10, weight: .semibold)).buttonStyle(.bordered).controlSize(.mini)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(.horizontal, isExpanded ? 20 : 15)
        .padding(.top, isExpanded ? 14 : 4)
        .padding(.bottom, isExpanded ? 18 : 10)
    }

    private func verseCard(_ suggestion: VerseSuggestion) -> some View {
        VStack(alignment: .leading, spacing: isExpanded ? 10 : 7) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(suggestion.reference).font(.system(size: isExpanded ? 25 : 19, weight: .semibold, design: .serif))
                    .lineLimit(1).minimumScaleFactor(0.82)
                Text(suggestion.translation).font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.13), in: Capsule())
                Spacer()
                Button { session.isPinned.toggle() } label: { Image(systemName: session.isPinned ? "pin.fill" : "pin") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help(session.isPinned ? "Unpin verse" : "Pin verse")
            }
            Text(suggestion.text)
                .font(.system(size: isExpanded ? 16 : 13, design: .serif))
                .lineSpacing(isExpanded ? 4 : 2)
                .lineLimit(isExpanded ? nil : 5)
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
                .onTapGesture { session.copy(suggestion.text) }
                .help("Click to copy verse text")
            HStack(spacing: 8) {
                Button { session.copy(suggestion.reference) } label: { Label("Copy reference", systemImage: "doc.on.doc") }
                    .buttonStyle(.borderedProminent)
                Button { session.copy(suggestion.text) } label: { Label("Copy verse", systemImage: "text.quote") }
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .padding(isExpanded ? 17 : 12)
        .background(.background.opacity(0.82), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(.white.opacity(0.55), lineWidth: 1))
    }

    private var listeningControls: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 9 : 5) {
            HStack {
                if isExpanded {
                    Text("LISTENING CONTROLS").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1)
                }
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { session.refreshDevices() }.labelStyle(.iconOnly).buttonStyle(.plain).help("Refresh audio inputs")
            }
            Picker("Audio input", selection: $session.selectedDeviceID) {
                Text("Choose an input…").tag(Int?.none)
                ForEach(session.devices) { device in Text(device.name).tag(Optional(device.id)) }
            }
            Picker("Translation", selection: $session.translation) {
                Text("KJV").tag("KJV")
                Text("NIV").tag("NIV")
                Text("NKJV").tag("NKJV")
                Text("NLT").tag("NLT")
            }
            HStack(spacing: 8) {
                Button { session.toggleListening() } label: {
                    Label(startButtonTitle, systemImage: startButtonSymbol)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StartListeningButtonStyle(isEnabled: !isStartDisabled))
                .disabled(isStartDisabled)
                .accessibilityHint(session.selectedDevice == nil ? "Choose an audio input to start listening." : "")
                Button("Stop", systemImage: "stop.fill") { session.stop() }
                    .buttonStyle(.bordered).disabled(session.state != .listening && session.state != .starting)
            }
            .controlSize(isExpanded ? .regular : .small)
        }
        .padding(.horizontal, isExpanded ? 20 : 15)
        .padding(.vertical, isExpanded ? 14 : 8)
        .background(.thinMaterial)
    }

    private var isStartDisabled: Bool {
        session.selectedDevice == nil || session.state == .starting || session.state == .loadingData || session.state == .loadingModel
    }

    private var startButtonTitle: String {
        switch session.state {
        case .starting: "Starting…"
        case .loadingData: "Preparing Bible data…"
        case .loadingModel: "Preparing speech model…"
        case .listening: "Pause listening"
        default: "Start listening"
        }
    }

    private var startButtonSymbol: String {
        session.state == .listening ? "pause.fill" : "mic.fill"
    }

    private var footer: some View {
        HStack {
            Button(action: openSettings) { Label("Open settings", systemImage: "gearshape") }
                .buttonStyle(.plain)
            Spacer()
            Text("\(session.engineName) · \(session.translation) search")
                .font(.system(size: 9)).foregroundStyle(.secondary)
            Button { session.shutdown(); NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain).help("Quit Devar")
        }
        .padding(.horizontal, isExpanded ? 20 : 15)
        .padding(.vertical, isExpanded ? 13 : 9)
    }
}

private struct SettingsView: View {
    @Bindable var session: DesktopSession
    @State private var selectedTab = "Audio"
    private let tabs = ["Audio", "Transcription", "Suggestions", "Appearance", "About"]

    var body: some View {
        NavigationSplitView {
            List(tabs, id: \.self, selection: $selectedTab) { tab in Label(tab, systemImage: icon(for: tab)).tag(tab) }
                .listStyle(.sidebar).navigationSplitViewColumnWidth(min: 155, ideal: 175)
        } detail: {
            Form {
                switch selectedTab {
                case "Audio": audioSettings
                case "Transcription": transcriptionSettings
                case "Suggestions": suggestionSettings
                case "Appearance": appearanceSettings
                default: aboutSettings
                }
            }
            .formStyle(.grouped).navigationTitle(selectedTab)
        }
    }

    private var audioSettings: some View {
        Section("Audio input") {
            Text("Choose the microphone or soundboard feed Devar listens to during a service.").foregroundStyle(.secondary)
            Picker("Input device", selection: $session.selectedDeviceID) {
                Text("Choose an input…").tag(Int?.none)
                ForEach(session.devices) { device in Text(device.name).tag(Optional(device.id)) }
            }
            Button("Refresh available inputs", systemImage: "arrow.clockwise") { session.refreshDevices() }
            if let device = session.selectedDevice {
                LabeledContent("Selected input", value: "\(device.name) · \(device.channels) channel\(device.channels == 1 ? "" : "s")")
            }
            if let error = session.errorMessage { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            Label("Listening begins only after you press Start. Audio is processed on this Mac and is not saved.", systemImage: "info.circle")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var transcriptionSettings: some View {
        Section("Speech recognition") {
            LabeledContent("Engine", value: session.engineName)
            LabeledContent("Model", value: "Medium Streaming")
            LabeledContent("Processing", value: "On this Mac")
            Text("The speech model is downloaded on first use and cached locally. After download, transcription can run without an internet connection.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var suggestionSettings: some View {
        Section("Bible suggestions") {
            LabeledContent("Bible data folder", value: session.bibleDirectory.isEmpty ? "Not selected" : URL(fileURLWithPath: session.bibleDirectory).lastPathComponent)
            Button("Choose Bible data folder…", systemImage: "folder") { session.chooseBibleDirectory() }
            Text("Choose a folder containing licensed Bible JSON files named by translation, such as nkjv.json. Bible text is not included with Devar.")
                .font(.callout).foregroundStyle(.secondary)
            Picker("Default translation", selection: $session.translation) {
                Text("KJV").tag("KJV")
                Text("NIV").tag("NIV")
                Text("NKJV").tag("NKJV")
                Text("NLT").tag("NLT")
            }
            Toggle("Keep pinned verse at the top", isOn: $session.isPinned)
            Stepper("Alternatives: \(max(1, session.suggestionCount))", value: $session.suggestionCount, in: 1...10)
            Stepper("Refresh every \(max(1, session.refreshSeconds)) seconds", value: $session.refreshSeconds, in: 1...15)
            Stepper("Rolling context: \(max(10, session.contextSeconds)) seconds", value: $session.contextSeconds, in: 10...120, step: 10)
            LabeledContent("Search", value: "Devar local scripture engine")
            if session.state == .listening {
                Text("Stop and restart listening to apply changed suggestion settings.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var appearanceSettings: some View {
        Section("Appearance") {
            LabeledContent("Appearance", value: "Follow macOS")
            Toggle("Launch at login", isOn: $session.launchAtLogin)
            Text("Devar opens in the menu bar when you sign in. The panel follows macOS appearance and accessibility settings.").font(.callout).foregroundStyle(.secondary)
        }
    }

    private var aboutSettings: some View {
        Section("About Devar Desktop") {
            Label("Local prototype", systemImage: "info.circle")
            Text("Live audio capture, on-device transcription, and verse ranking are connected. Intel Macs use CPU transcription; semantic search is available only on Apple silicon.")
                .foregroundStyle(.secondary)
        }
    }

    private func icon(for tab: String) -> String {
        switch tab {
        case "Audio": "waveform"
        case "Transcription": "waveform.badge.mic"
        case "Suggestions": "text.book.closed"
        case "Appearance": "paintbrush"
        default: "info.circle"
        }
    }
}
