import SwiftUI
import ProbeCore
import AOTCore
import Darwin

@main
struct RuntimeProbeApp: App {
    var body: some Scene { WindowGroup { ProbeView() } }
}

private struct ProbeView: View {
    @State private var report = ProbeRunner.baseline()
    @State private var lastExperiment = "Not run"
    @State private var aotReport: AOTReport?
    @State private var aotRunning = false
    @State private var aotError: String?

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return "\(version) (\(build))"
    }

    private var aotReportText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = aotReport.flatMap { try? encoder.encode($0) } ?? Data()
        return "App: AOT Runtime Control \(appVersion)\nDevice: \(machine())\nSystem: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)\n" + String(decoding: data, as: UTF8.self)
    }

    private var reportText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = (try? encoder.encode(report)) ?? Data()
        return "Device: \(machine())\nSystem: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)\nExperiment: \(lastExperiment)\n" +
            String(decoding: data, as: UTF8.self)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Diagnostic experiment") {
                    Text("Partial Multiplayer bootstrap experiment")
                    Text("Signed AOT runs a finite translated initialization path through its first log. Gameplay, rendering and JIT remain unproven.")
                        .font(.footnote)
                }
                Section("Real MP initialization · \(appVersion)") {
                    Button(aotRunning ? "Running translated initialization…" : "3. Run signed MP AOT bootstrap") {
                        aotRunning = true
                        aotError = nil
                        aotReport = nil
                        Task { @MainActor in
                            defer { aotRunning = false }
                            do {
                                aotReport = try await Task.detached(priority: .userInitiated) { try AOTRunner.run() }.value
                            } catch {
                                aotError = error.localizedDescription
                            }
                        }
                    }
                    .disabled(aotRunning)
                    .accessibilityIdentifier("run-aot-bootstrap")
                    if let value = aotReport {
                        Text("AOT result: \(value.status)").accessibilityIdentifier("aot-result")
                        Text(value.message).font(.system(.footnote, design: .monospaced)).accessibilityIdentifier("aot-message")
                        Text("Translated instructions: \(value.steps) · host calls: \(value.hostCalls)")
                        Text("Signed native \(value.nativeArchitecture) · JIT unused")
                        Text("The verified ELF snapshot was loaded and relocated at build time.").font(.footnote)
                        ShareLink("Share AOT measured report", item: aotReportText)
                    }
                    if let value = aotError { Text(value).foregroundStyle(.red) }
                }
                Section("Run manually") {
                    Button("1. Signed ARM64 baseline") {
                        lastExperiment = "Signed full-pointer baseline"
                        report = ProbeRunner.runSignedRoundtrip(input: 7)
                    }
                    Button("2. Low-memory callback experiment") {
                        lastExperiment = "Low-memory context32 experiment"
                        report = ProbeRunner.run(input: 11)
                    }
                }
                Section("Result: \(report.status)") {
                    Text(report.detail)
                    Text("Page size: \(report.pageSize) bytes")
                    Text("Signed entry: 0x\(String(report.signedEntryAddress, radix: 16))")
                    Text("Data: 0x\(String(report.dataAddress, radix: 16))")
                    Text("Stack: 0x\(String(report.stackStart, radix: 16))–0x\(String(report.stackEnd, radix: 16))")
                    Text("errno: \(report.errorNumber)")
                    Text("ILP32 guest entry: NOT PROVEN")
                    Text("Executable memory/JIT: NOT TESTED")
                    ShareLink("Share measured report", item: reportText)
                }
                Section("Raw measured report") {
                    Text(reportText).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }
            .navigationTitle("AOT Runtime Control")
        }
    }

    private func machine() -> String {
        var length = 0
        guard sysctlbyname("hw.machine", nil, &length, nil, 0) == 0, length > 0 else { return UIDevice.current.model }
        var value = [CChar](repeating: 0, count: length)
        guard sysctlbyname("hw.machine", &value, &length, nil, 0) == 0 else { return UIDevice.current.model }
        return String(cString: value)
    }
}
