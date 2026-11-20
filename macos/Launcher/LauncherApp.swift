import AppKit
@preconcurrency import AVFoundation
import Combine
import SwiftUI

@main
struct LauncherApp: App {
    @NSApplicationDelegateAdaptor(LauncherDelegate.self) private var delegate
    @StateObject private var meeting = MeetingLauncher()

    var body: some Scene {
        Window("Silent Meeting", id: "meeting") {
            LauncherView(meeting: meeting)
                .padding(24)
                .frame(minWidth: 625, minHeight: 565)
        }
        .defaultSize(width: 720, height: 640)
        .windowResizability(.contentMinSize)
    }
}

final class LauncherDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct LauncherView: View {
    @ObservedObject var meeting: MeetingLauncher
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("Silent Meeting")
                    .font(.system(size: 39, weight: .semibold, design: .serif))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Label(meeting.live ? "Camera live" : "Camera idle",
                      systemImage: meeting.live ? "video.fill" : "video.slash")
                    .foregroundStyle(meeting.live ? Color.green : Color.secondary)
            }

            ZStack {
                Color(white: 0.05)
                if let image = meeting.preview {
                    Image(decorative: image, scale: 1)
                        .resizable().scaledToFit().accessibilityLabel("Silent film preview")
                } else {
                    Text("Camera preview")
                        .foregroundStyle(Color(white: 0.73))
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 10))

            if !meeting.ready || meeting.preparing != nil {
                setup
            }

            HStack(spacing: 18) {
                Picker("Camera", selection: $meeting.cameraID) {
                    if meeting.cameras.isEmpty { Text("No camera found").tag("") }
                    ForEach(meeting.cameras, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                }
                Picker("Speech mic", selection: $meeting.microphoneID) {
                    if meeting.microphones.isEmpty { Text("No microphone found").tag("") }
                    ForEach(meeting.microphones, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                }
            }
            .disabled(meeting.running || meeting.starting)

            HStack {
                Button(meeting.running ? "Stop" : "Start") {
                    meeting.running ? meeting.stop() : meeting.start()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(meeting.starting || (!meeting.running && !meeting.canStart))
                Toggle("Start on launch", isOn: $meeting.startOnLaunch)
                    .toggleStyle(.checkbox)
                Spacer()
                if meeting.running {
                    Label("Piano routed", systemImage: "music.note").foregroundStyle(.secondary)
                }
            }

            Text(meeting.message ?? meeting.setupHint)
            .fixedSize(horizontal: false, vertical: true)
            .font(.callout)
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .onAppear { meeting.refresh() }
        .onReceive(timer) { _ in meeting.refresh() }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("One-time setup").font(.headline).accessibilityAddTraits(.isHeader)

            HStack {
                Label(meeting.cameraReady ? "OBS Virtual Camera ready" : "OBS Virtual Camera",
                      systemImage: meeting.cameraReady ? "checkmark.circle.fill" : "video")
                Spacer()
                if !meeting.obsInstalled {
                    Button("Install OBS") { meeting.install(.obs) }
                } else if !meeting.cameraReady {
                    Button("Open System Settings") { NSWorkspace.shared.open(LauncherSetup.settings) }
                    Button("Enable in OBS") { meeting.openOBS() }
                } else if meeting.obsRunning {
                    Button("Quit OBS") { meeting.quitOBS() }
                }
            }
            HStack {
                Label(meeting.audioReady ? "BlackHole 2ch ready" : "BlackHole 2ch",
                      systemImage: meeting.audioReady ? "checkmark.circle.fill" : "music.note")
                Spacer()
                if !meeting.audioReady {
                    if meeting.driverInstalled {
                        Text("Restart Mac after installation").foregroundStyle(.secondary)
                    } else {
                        Button("Install BlackHole") { meeting.install(.blackHole) }
                    }
                } else if meeting.outputConflict {
                    Button("Open System Settings") { NSWorkspace.shared.open(LauncherSetup.settings) }
                }
            }
            if meeting.outputConflict {
                Text("Choose speakers or headphones as your Mac's sound output to keep other sounds out of BlackHole.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let preparing = meeting.preparing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(preparing).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.42), in: .rect(cornerRadius: 8))
        .disabled(meeting.preparing != nil)
    }
}

final class MeetingLauncher: ObservableObject, @unchecked Sendable {
    enum Dependency { case obs, blackHole }

    @Published var cameraID = UserDefaults.standard.string(forKey: "meetingCamera") ?? ""
    @Published var microphoneID = UserDefaults.standard.string(forKey: "speechMicrophone") ?? ""
    @Published var startOnLaunch = UserDefaults.standard.object(forKey: "startOnLaunch") as? Bool ?? true {
        didSet { UserDefaults.standard.set(startOnLaunch, forKey: "startOnLaunch") }
    }
    @Published private(set) var cameras: [AVCaptureDevice] = []
    @Published private(set) var microphones: [AVCaptureDevice] = []
    @Published private(set) var obsInstalled = false
    @Published private(set) var obsRunning = false
    @Published private(set) var driverInstalled = false
    @Published private(set) var cameraReady = false
    @Published private(set) var audioReady = false
    @Published private(set) var outputConflict = false
    @Published private(set) var starting = false
    @Published private(set) var running = false
    @Published private(set) var live = false
    @Published private(set) var preview: CGImage?
    @Published private(set) var message: String?
    @Published private(set) var preparing: String?

    private let worker = DispatchQueue(label: "Silent Meeting session setup", qos: .userInitiated)
    private var capture: CapturePipeline?
    private var piano: BlackHolePiano?
    private var sessionID: UUID?
    private var autoStartTried = false
    private var lastPreview = DispatchTime(uptimeNanoseconds: 0)
    private var waitingSince: DispatchTime?

    var ready: Bool { obsInstalled && cameraReady && audioReady && !outputConflict && !obsRunning }
    var canStart: Bool { ready && preparing == nil && !cameraID.isEmpty && !microphoneID.isEmpty }
    var setupHint: String {
        if obsRunning && cameraReady { return "Quit OBS Studio to free its virtual camera for Silent Meeting." }
        if ready { return "In your meeting app, select OBS Virtual Camera and BlackHole 2ch." }
        return "Complete setup to make both devices available in your meeting app."
    }

    func refresh() {
        obsInstalled = LauncherSetup.obsInstalled
        obsRunning = !LauncherSetup.obsRunning.isEmpty
        driverInstalled = FileManager.default.fileExists(atPath: LauncherSetup.blackHoleDriver.path)
        cameraReady = obsInstalled && CameraSink.available(.obs)
        audioReady = BlackHolePiano.deviceAvailable
        outputConflict = audioReady && BlackHolePiano.systemOutputUsesBlackHole

        let video = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                                     mediaType: .video, position: .unspecified).devices
        let audio = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone],
                                                     mediaType: .audio, position: .unspecified).devices
        cameras = video.filter {
            let id = $0.uniqueID
            return id.caseInsensitiveCompare(CameraSink.Target.obs.uid) != .orderedSame &&
                id.caseInsensitiveCompare(CameraFormat.deviceID.uuidString) != .orderedSame &&
                $0.localizedName != "OBS Virtual Camera" && $0.localizedName != CameraFormat.name
        }
        microphones = audio.filter {
            !$0.uniqueID.lowercased().hasPrefix("blackhole") &&
                !$0.localizedName.lowercased().hasPrefix("blackhole") &&
                $0.uniqueID != "io.github.xaroth8088.silent-meeting.piano-input" &&
                $0.localizedName != "Silent Meeting Piano"
        }

        let inputsAvailable = cameras.contains { $0.uniqueID == cameraID } &&
            microphones.contains { $0.uniqueID == microphoneID }
        if running && !starting && (!ready || !inputsAvailable) {
            stop()
            message = obsRunning ? "Stop OBS and start Silent Meeting again to use its virtual camera." :
                "A camera or audio device is unavailable. Reconnect it to continue."
        } else if !running && !starting {
            if !cameras.contains(where: { $0.uniqueID == cameraID }) { cameraID = cameras.first?.uniqueID ?? "" }
            if !microphones.contains(where: { $0.uniqueID == microphoneID }) { microphoneID = microphones.first?.uniqueID ?? "" }
        }

        if running && !starting && DispatchTime.now() >= lastPreview + .seconds(4) {
            live = false
            message = "Waiting for frames from your camera."
        }
        if !autoStartTried && canStart && startOnLaunch && UserDefaults.standard.bool(forKey: "meetingSetupComplete") {
            start()
        }
    }

    func install(_ dependency: Dependency) {
        guard preparing == nil else { return }
        preparing = dependency == .obs ? "Downloading and verifying OBS…" : "Downloading and verifying BlackHole…"
        message = nil
        Task { @MainActor [self] in
            defer {
                preparing = nil
                refresh()
            }
            do {
                switch dependency {
                case .obs:
                    switch try await LauncherSetup.installOBS() {
                    case .installed:
                        openOBS()
                    case .openDiskImage(let dmg):
                        guard NSWorkspace.shared.open(dmg) else { throw LauncherError.open(dmg.lastPathComponent) }
                        message = "Drag OBS into Applications, then return here and click Enable in OBS."
                    }
                case .blackHole:
                    let installer = try await LauncherSetup.blackHole.fetch()
                    guard NSWorkspace.shared.open(installer) else { throw LauncherError.open(installer.lastPathComponent) }
                    message = "Finish the BlackHole installer and restart your Mac."
                }
            } catch {
                message = error.localizedDescription
            }
        }
    }

    func openOBS() {
        guard LauncherSetup.obsInstalled, NSWorkspace.shared.open(LauncherSetup.obsApp) else {
            message = "Install OBS in Applications to enable its camera."
            return
        }
        message = "Approve OBS Virtual Camera in System Settings when prompted. Once it's ready, quit OBS."
    }

    func quitOBS() {
        for app in LauncherSetup.obsRunning { _ = app.terminate() }
        message = nil
    }

    func start() {
        guard canStart, !starting, !running,
              let camera = cameras.first(where: { $0.uniqueID == cameraID }),
              let microphone = microphones.first(where: { $0.uniqueID == microphoneID }),
              let soundtracks = Bundle.main.resourceURL
        else { return }

        autoStartTried = true
        starting = true
        message = nil
        Task { @MainActor [self] in
            let videoAllowed = await AVCaptureDevice.requestAccess(for: .video)
            let audioAllowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard videoAllowed && audioAllowed else {
                starting = false
                message = "Allow Silent Meeting to use your camera and microphone in System Settings → Privacy & Security."
                return
            }
            guard LauncherSetup.obsRunning.isEmpty else {
                starting = false
                message = "Quit OBS to let Silent Meeting use its virtual camera."
                return
            }
            let id = UUID()
            let mic = BlackHolePiano()
            sessionID = id
            waitingSince = .now()
            let pipeline = CapturePipeline(target: .obs, changeMusic: { [weak mic] mood in
                mic?.select(mood)
            }) { [weak self] image, sending in
                DispatchQueue.main.async {
                    guard let self, self.sessionID == id else { return }
                    self.preview = image
                    self.lastPreview = .now()
                    self.live = sending
                    if sending {
                        self.waitingSince = nil
                        if self.running { self.message = nil }
                    } else {
                        if self.waitingSince == nil { self.waitingSince = .now() }
                        if let since = self.waitingSince, DispatchTime.now() >= since + .seconds(3) {
                            self.message = "Couldn't connect to OBS Virtual Camera. Check that OBS is closed and its camera extension is enabled."
                        }
                    }
                }
            }
            capture = pipeline
            piano = mic
            worker.async {
                let result = Result {
                    try pipeline.start(camera: camera, microphone: microphone)
                    do { try mic.start(soundtracks: soundtracks) } catch {
                        pipeline.stop()
                        throw error
                    }
                }
                DispatchQueue.main.async {
                    self.starting = false
                    switch result {
                    case .success:
                        self.running = true
                        self.lastPreview = .now()
                        UserDefaults.standard.set(true, forKey: "meetingSetupComplete")
                        UserDefaults.standard.set(camera.uniqueID, forKey: "meetingCamera")
                        UserDefaults.standard.set(microphone.uniqueID, forKey: "speechMicrophone")
                    case .failure(let error):
                        self.sessionID = nil
                        self.capture = nil
                        self.piano = nil
                        self.live = false
                        self.preview = nil
                        self.message = error.localizedDescription
                    }
                }
            }
        }
    }

    func stop() {
        guard let capture, let piano, !starting else { return }
        sessionID = nil
        starting = true
        live = false
        worker.async {
            piano.stop()
            capture.stop()
            DispatchQueue.main.async {
                self.capture = nil
                self.piano = nil
                self.running = false
                self.starting = false
                self.preview = nil
            }
        }
    }
}

private enum LauncherError: LocalizedError {
    case open(String)

    var errorDescription: String? {
        switch self {
        case .open(let filename): return "macOS couldn't open \(filename)."
        }
    }
}
