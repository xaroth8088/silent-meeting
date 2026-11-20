import AppKit
import CryptoKit
import Foundation

enum LauncherSetup {
    static let obsID = "com.obsproject.obs-studio"
    static let obsApp = URL(fileURLWithPath: "/Applications/OBS.app", isDirectory: true)
    static let blackHoleDriver = URL(fileURLWithPath: "/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver", isDirectory: true)
    static let settings = URL(fileURLWithPath: "/System/Applications/System Settings.app", isDirectory: true)

    struct Download {
        let url: URL
        let sha256: String

        func verified(_ file: URL) throws -> Bool {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            var hasher = SHA256()
            while let block = try handle.read(upToCount: 1_048_576), !block.isEmpty { hasher.update(data: block) }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined() == sha256
        }

        func fetch() async throws -> URL {
            let directory = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true)
                .appendingPathComponent("Silent Meeting/Installers", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let cached = directory.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: cached.path) {
                if try verified(cached) { return cached }
                try FileManager.default.removeItem(at: cached)
            }
            let (file, response) = try await URLSession.shared.download(from: url)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw SetupError.download
            }
            defer { try? FileManager.default.removeItem(at: file) }
            guard try verified(file) else { throw SetupError.checksum }
            try FileManager.default.moveItem(at: file, to: cached)
            return cached
        }
    }

    static var obsDownload: Download {
        let arm = "f9cd96511c5efdd3ffd9a0068e3bbc276c61fc451d1004e3eea5658a9cb70488"
        let intel = "84eb584a89cdef83f3385655e348496dbb0715459be249afa1c6787d60d2cc33"
        // An Intel launcher under Rosetta must still install the native Apple Silicon OBS.
        var available: Int32 = 0
        var size = MemoryLayout.size(ofValue: available)
        let silicon = sysctlbyname("hw.optional.arm64", &available, &size, nil, 0) == 0 && available != 0
        let suffix = silicon ? "Apple" : "Intel"
        return Download(url: URL(string: "https://github.com/obsproject/obs-studio/releases/download/33.0.2/OBS-Studio-33.0.2-macOS-\(suffix).dmg")!,
                        sha256: silicon ? arm : intel)
    }

    static let blackHole = Download(
        url: URL(string: "https://existential.audio/downloads/BlackHole2ch-0.7.1.pkg")!,
        sha256: "57b540f27a3e29c37e310e01bee0fdfab76733087e47f997ef9dccf851400dcf"
    )

    static var obsInstalled: Bool {
        Bundle(url: obsApp)?.bundleIdentifier == obsID &&
            FileManager.default.fileExists(atPath: obsApp.appendingPathComponent(
                "Contents/Library/SystemExtensions/com.obsproject.obs-studio.mac-camera-extension.systemextension"
            ).path)
    }

    static var obsRunning: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: obsID).filter { !$0.isTerminated }
    }

    enum OBSInstall {
        case installed
        case openDiskImage(URL)
    }

    static func installOBS() async throws -> OBSInstall {
        if obsInstalled { return .installed }
        let dmg = try await obsDownload.fetch()
        let target = obsApp.deletingLastPathComponent()
        // Let Finder request authorization when Applications is not writable or an OBS bundle exists.
        guard FileManager.default.isWritableFile(atPath: target.path),
              !FileManager.default.fileExists(atPath: obsApp.path) else { return .openDiskImage(dmg) }

        let mount = FileManager.default.temporaryDirectory.appendingPathComponent("silent-obs-\(UUID())")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: false)
        defer { try? run("/bin/rmdir", [mount.path]) }
        try run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-mountpoint", mount.path, dmg.path])
        defer { try? run("/usr/bin/hdiutil", ["detach", mount.path]) }
        let source = mount.appendingPathComponent("OBS.app")
        guard Bundle(url: source)?.bundleIdentifier == obsID else { throw SetupError.obsBundle }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", source.path])

        let staged = target.appendingPathComponent(".silent-obs-\(UUID()).app")
        defer { try? FileManager.default.removeItem(at: staged) }
        do {
            try run("/usr/bin/ditto", [source.path, staged.path])
            try FileManager.default.moveItem(at: staged, to: obsApp)
        } catch {
            return .openDiskImage(dmg)
        }
        return .installed
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw SetupError.helper(executable, process.terminationStatus) }
    }
}

private enum SetupError: LocalizedError {
    case download, checksum, obsBundle, helper(String, Int32)

    var errorDescription: String? {
        switch self {
        case .download: return "The official installer couldn't be downloaded. Try again."
        case .checksum: return "The installer doesn't match its published checksum. Get it from the vendor's website."
        case .obsBundle: return "The OBS app couldn't be found in the downloaded disk image."
        case .helper(let path, let code): return "\(URL(fileURLWithPath: path).lastPathComponent) failed (\(code))."
        }
    }
}
