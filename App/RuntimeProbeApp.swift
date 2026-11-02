import SwiftUI
import ProbeCore
import Darwin

@main
struct RuntimeProbeApp: App {
    var body: some Scene { WindowGroup { ProbeView() } }
}

private struct ProbeView: View {
    @State private var report = ProbeRunner.baseline()
    @State private var lastExperiment = "Not run"

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
                    Text("This app does not contain or run Black Ops II.")
                    Text("A signed synthetic callback tests stack, registers and thread state. Guest entry32, engine TLS and JIT remain unproven.")
                        .font(.footnote)
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
            .navigationTitle("Runtime Probe")
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
