import Foundation
import CProbe

public enum LowAddressRange {
    public static func isValid(address: UInt64, byteCount: UInt64) -> Bool {
        let limit: UInt64 = 0x1_0000_0000
        return address > 0 && byteCount > 0 && address < limit && byteCount <= limit - address
    }
}

public struct ProbeObservation {
    public let lowMemory: Bool
    public let callbackCount: UInt32
    public let canaries: Bool
    public let tls: Bool
    public let returnValue: UInt64
    public let expectedReturn: UInt64

    public init(lowMemory: Bool, callbackCount: UInt32, canaries: Bool, tls: Bool,
                returnValue: UInt64, expectedReturn: UInt64) {
        self.lowMemory = lowMemory; self.callbackCount = callbackCount
        self.canaries = canaries; self.tls = tls
        self.returnValue = returnValue; self.expectedReturn = expectedReturn
    }
}

public enum ProbeAssessment {
    public static func passed(_ observation: ProbeObservation) -> Bool {
        observation.lowMemory && observation.callbackCount == 1 && observation.canaries &&
        observation.tls && observation.returnValue == observation.expectedReturn
    }
}

public struct ProbeReport: Codable {
    public var status = "not_run"
    public var detail = "No experiment has run. This app does not contain the BO2 engine."
    public var pageSize: UInt64 = 0
    public var mappingAddress: UInt64 = 0
    public var mappingSize: UInt64 = 0
    public var dataAddress: UInt64 = 0
    public var stackStart: UInt64 = 0
    public var stackEnd: UInt64 = 0
    public var callbackStack: UInt64 = 0
    public var signedEntryAddress: UInt64 = 0
    public var result: UInt64 = 0
    public var expectedResult: UInt64 = 0
    public var errorNumber: Int32 = 0
    public var callbackExecuted = false
    public var tlsPreserved = false
    public var canariesPreserved = false
    public var stackPreserved = false
    public var registerCanariesPreserved = false
    public var context32Proven = false
    public var ilp32EntryProven = false
    public var executableMemoryStatus = "not_tested"
    public var mappingPermissions = "guard: none; data/stack: read+write; no executable mapping"
}

public enum ProbeRunner {
    public static func baseline() -> ProbeReport {
        var report = ProbeReport()
        report.pageSize = probe_page_size()
        return report
    }

    public static func run(input: UInt32) -> ProbeReport { measure(input: input, low: true) }
    public static func runSignedRoundtrip(input: UInt32) -> ProbeReport { measure(input: input, low: false) }

    private static func measure(input: UInt32, low: Bool) -> ProbeReport {
        let native = probe_run(input, low)
        var report = baseline()
        report.status = ["passed", "unavailable", "unsupported", "protection_error", "invariant_failed"][min(Int(native.status), 4)]
        report.detail = low ? "Low-memory synthetic callback. Guest entry32 and BO2 execution are not proven." :
            "Signed full-pointer ARM64 callback on a guarded stack. This does not prove ILP32 compatibility."
        if native.status == 1 { report.detail = "No usable mapping was reserved; errno=\(native.error_number). No callback executed." }
        if native.status == 2 { report.detail = "Architecture/platform unsupported; no assembly or callback executed." }
        report.errorNumber = native.error_number
        report.pageSize = native.page_size
        report.mappingAddress = native.mapping_address
        report.mappingSize = native.mapping_size
        report.dataAddress = native.data_address
        report.stackStart = native.stack_start
        report.stackEnd = native.stack_end
        report.callbackStack = native.callback_stack
        report.signedEntryAddress = native.signed_entry
        report.result = native.returned
        report.expectedResult = native.expected
        report.callbackExecuted = native.callback_count == 1
        report.tlsPreserved = native.tls_preserved != 0
        report.canariesPreserved = native.canaries_preserved != 0
        report.stackPreserved = native.stack_preserved != 0
        report.registerCanariesPreserved = native.register_preserved != 0
        report.context32Proven = native.context32 != 0 && native.status == 0
        // Calling a signed function through a full pointer never proves entry32.
        report.ilp32EntryProven = false
        return report
    }
}
