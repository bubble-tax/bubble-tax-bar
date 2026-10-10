import Foundation
import Darwin
import BubbleTaxBarCore

/// Keeps provider quota collection independent of the optional Python log parser.
enum NativeUsageCollector {
    static func collect(binary: String, providers: [Provider]) async -> ([ProviderConnection], [QuotaWindow]) {
        await withTaskGroup(of: (ProviderConnection, [QuotaWindow]).self) { group in
            for provider in providers {
                group.addTask { await Task.detached(priority: .utility) { fetch(binary: binary, provider: provider) }.value }
            }
            var connections: [ProviderConnection] = [], windows: [QuotaWindow] = []
            for await (connection, quotas) in group { connections.append(connection); windows += quotas }
            connections.sort { $0.provider.rawValue < $1.provider.rawValue }
            return (connections, windows)
        }
    }

    private static func fetch(binary: String, provider: Provider) -> (ProviderConnection, [QuotaWindow]) {
        var result = try! LiveUsageNormalizer.normalize(Data("{}".utf8), provider: provider)
        guard let id = LiveUsageNormalizer.helperID(provider) else { return result }
        let sources = provider == .openai ? ["oauth", "cli"] : provider == .claude ? ["oauth", "auto"] : ["auto"]
        for source in sources {
            if let bytes = try? CollectorProcess.run(binary, arguments: ["usage", "--provider", id, "--source", source,
                    "--format", "json", "--no-credits"], timeout: 25),
               let candidate = try? LiveUsageNormalizer.normalize(bytes, provider: provider) {
                if !candidate.1.isEmpty { return candidate }
                if candidate.0.status == "connected" { result = candidate }
            }
        }
        if provider == .claude, let cached = cachedClaude() { return cached }
        return result
    }

    private static func cachedClaude() -> (ProviderConnection, [QuotaWindow])? {
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let current = support.appendingPathComponent("BubbleTaxBar/claude-statusline")
        let legacy = support.appendingPathComponent("SubRIP/claude-statusline")
        let folder = !FileManager.default.fileExists(atPath: current.appendingPathComponent("configuration.json").path) &&
            FileManager.default.fileExists(atPath: legacy.appendingPathComponent("configuration.json").path) ? legacy : current
        let file = folder.appendingPathComponent("quota.json")
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 16384,
              let bytes = try? Data(contentsOf: file),
              let raw = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let windows = raw["windows"],
              let data = try? JSONSerialization.data(withJSONObject: windows),
              let decoded = try? JSONDecoder().decode([QuotaWindow].self, from: data) else { return nil }
        let now = Date().timeIntervalSince1970
        let sanitized = decoded.compactMap { window -> QuotaWindow? in
            guard [300, 10080].contains(window.windowMinutes), window.usedPercent.isFinite,
                  (0...100).contains(window.usedPercent), window.observedAt.isFinite,
                  (0...900).contains(now - window.observedAt), window.resetsAt.isFinite,
                  window.resetsAt > now, window.resetsAt <= window.observedAt + Double(window.windowMinutes * 60 + 60) else { return nil }
            return QuotaWindow(provider: .claude, limitID: window.windowMinutes == 300 ? "claude:primary" : "claude:secondary",
                windowMinutes: window.windowMinutes, resetsAt: window.resetsAt, observedAt: window.observedAt, usedPercent: window.usedPercent)
        }
        guard let latest = sanitized.map(\.observedAt).max() else { return nil }
        let connection = try! JSONDecoder().decode(ProviderConnection.self, from: JSONSerialization.data(withJSONObject:
            ["provider": "claude", "status": "connected", "source": "local statusline", "observedAt": latest]))
        return (connection, sanitized)
    }
}

enum CollectorProcess {
    static func localHelper() -> String? {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/BubbleTaxCollector.app/Contents/MacOS/BubbleTaxCollector").path
        let developer = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("dist/collector/BubbleTaxCollector.app/Contents/MacOS/BubbleTaxCollector").path
        return [bundled, developer].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    enum Failure: LocalizedError {
        case failed, timedOut, oversized
        var errorDescription: String? {
            switch self {
            case .failed: return "The collector could not complete this request."
            case .timedOut: return "The collector timed out. Refresh to try again."
            case .oversized: return "The collector response was too large."
            }
        }
    }
    private final class Buffer: @unchecked Sendable {
        let lock = NSLock()
        var data = Data()
        var oversized = false
        func append(_ bytes: Data) -> Bool {
            lock.lock(); defer { lock.unlock() }
            if data.count + bytes.count > 2 * 1024 * 1024 { oversized = true; return false }
            data.append(bytes); return true
        }
    }
    static func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> Data {
        let process = Process(), pipe = Pipe(), buffer = Buffer()
        let finished = DispatchSemaphore(value: 0), reader = DispatchGroup()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" +
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        reader.enter()
        DispatchQueue.global(qos: .utility).async {
            defer { reader.leave() }
            while let bytes = try? pipe.fileHandleForReading.read(upToCount: 65536), !bytes.isEmpty {
                if !buffer.append(bytes) { if process.isRunning { process.terminate() }; break }
            }
        }
        defer { try? pipe.fileHandleForReading.close(); try? pipe.fileHandleForWriting.close() }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            if process.isRunning { process.terminate() }
            if finished.wait(timeout: .now() + 1) == .timedOut, process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw Failure.timedOut
        }
        guard reader.wait(timeout: .now() + 1) == .success else { throw Failure.timedOut }
        buffer.lock.lock(); defer { buffer.lock.unlock() }
        guard !buffer.oversized else { throw Failure.oversized }
        guard process.terminationStatus == 0 else { throw Failure.failed }
        return buffer.data
    }

}
