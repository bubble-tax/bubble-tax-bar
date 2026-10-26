import XCTest
@testable import BubbleTaxBar

final class CollectorProcessTests: XCTestCase {
    func testNoPythonDoesNotPreventProviderCollection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let helper = directory.appendingPathComponent("helper")
        let script = """
        #!/bin/sh
        printf '%s' '{"source":"oauth","usage":{"updatedAt":"2026-10-08T10:00:00Z","identity":{"loginMethod":"Plus"},"primary":{"usedPercent":25,"windowMinutes":300,"resetsAt":"2026-10-08T12:00:00Z"}}}'
        """
        try script.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let result = await NativeUsageCollector.collect(binary: helper.path, providers: [.openai])
        XCTAssertEqual(result.0.first?.status, "connected")
        XCTAssertEqual(result.1.first?.remainingPercent, 75)
    }
    func testClaudeUsesExplicitCLIWhenOAuthCannotReadCurrentCredentials() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let helper = directory.appendingPathComponent("helper")
        let script = """
        #!/bin/sh
        case "$*" in
          *"--source cli"*) printf '%s' '{"source":"claude","usage":{"updatedAt":"2026-10-26T10:00:00Z","identity":{"loginMethod":"Max","accountEmail":"test@example.invalid"},"primary":{"usedPercent":25,"windowMinutes":300,"resetsAt":"2026-10-26T12:00:00Z"},"secondary":{"usedPercent":61,"windowMinutes":10080,"resetsAt":"2026-10-29T12:00:00Z"}}}' ;;
          *) exit 1 ;;
        esac
        """
        try script.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let result = await NativeUsageCollector.collect(binary: helper.path, providers: [.claude])
        XCTAssertEqual(result.0.first?.status, "connected")
        XCTAssertEqual(result.0.first?.planLabel, "Max")
        XCTAssertNotNil(result.0.first?.accountKey)
        XCTAssertEqual(result.1.count, 2)
        XCTAssertEqual(result.1.last?.usedPercent, 61)
        // A successful but anonymous OAuth response must not block the CLI fallback.
        let anonymous = script.replacingOccurrences(of: "*) exit 1 ;;", with: "*) printf '%s' '{\"source\":\"oauth\",\"usage\":{\"updatedAt\":\"2026-10-26T10:00:00Z\",\"primary\":{\"usedPercent\":5,\"windowMinutes\":300,\"resetsAt\":\"2026-10-26T12:00:00Z\"}}}' ;;")
        try anonymous.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let recovered = await NativeUsageCollector.collect(binary: helper.path, providers: [.claude])
        XCTAssertNotNil(recovered.0.first?.accountKey)
        XCTAssertEqual(recovered.0.first?.source, "Claude CLI")
        XCTAssertEqual(recovered.1.first?.usedPercent, 25)
    }
    func testBoundedCollectorOutput() throws {
        let data = try CollectorProcess.run("/bin/sh", arguments: ["-c", "printf 'result'"], timeout: 2)
        XCTAssertEqual(String(data: data, encoding: .utf8), "result")
    }
    func testNonzeroExitIsFailure() {
        XCTAssertThrowsError(try CollectorProcess.run("/bin/sh", arguments: ["-c", "exit 7"], timeout: 2))
    }
    func testTimeoutStopsAStuckCollector() {
        let start = Date()
        XCTAssertThrowsError(try CollectorProcess.run("/bin/sh", arguments: ["-c", "exec sleep 20"], timeout: 0.1))
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }
    func testOversizedOutputIsRejected() {
        XCTAssertThrowsError(try CollectorProcess.run("/usr/bin/head", arguments: ["-c", "2200000", "/dev/zero"], timeout: 2))
    }
}
