import XCTest
import ProbeCore

final class ProbeCoreTests: XCTestCase {
    func testRangeAcceptsWholeLowWindowIncludingLastByte() {
        XCTAssertTrue(LowAddressRange.isValid(address: 0x10000, byteCount: 0x4000))
        XCTAssertTrue(LowAddressRange.isValid(address: 0xffff_ffff, byteCount: 1))
    }

    func testRangeRejectsNullEmptyOverflowAndCrossingLimit() {
        XCTAssertFalse(LowAddressRange.isValid(address: 0, byteCount: 4096))
        XCTAssertFalse(LowAddressRange.isValid(address: 0x10000, byteCount: 0))
        XCTAssertFalse(LowAddressRange.isValid(address: 0xffff_ffff, byteCount: 2))
        XCTAssertFalse(LowAddressRange.isValid(address: UInt64.max - 1, byteCount: 8))
        XCTAssertFalse(LowAddressRange.isValid(address: 0x1_0000_0000, byteCount: 1))
    }

    func testMemoryCallbackAssessmentRejectsIncorrectReturn() {
        let good = ProbeObservation(lowMemory: true, callbackCount: 1, canaries: true,
                                    tls: true, returnValue: 46, expectedReturn: 46)
        XCTAssertTrue(ProbeAssessment.passed(good))
        let wrongReturn = ProbeObservation(lowMemory: true, callbackCount: 1, canaries: true,
                                           tls: true, returnValue: 45, expectedReturn: 46)
        XCTAssertFalse(ProbeAssessment.passed(wrongReturn))
    }

    func testAssessmentRejectsMissingCallbackAndChangedTLS() {
        XCTAssertFalse(ProbeAssessment.passed(.init(lowMemory: true, callbackCount: 0,
            canaries: true, tls: true, returnValue: 46, expectedReturn: 46)))
        XCTAssertFalse(ProbeAssessment.passed(.init(lowMemory: true, callbackCount: 1,
            canaries: true, tls: false, returnValue: 46, expectedReturn: 46)))
    }

    func testBaselineNeverClaimsGuestOrLowEntryExecution() {
        let report = ProbeRunner.baseline()
        XCTAssertEqual(report.status, "not_run")
        XCTAssertFalse(report.callbackExecuted)
        XCTAssertFalse(report.ilp32EntryProven)
        XCTAssertGreaterThan(report.pageSize, 0)
    }

    func testSignedRoundtripReallyExecutesForDistinctInputs() throws {
        for input: UInt32 in [1, 7] {
            let report = ProbeRunner.runSignedRoundtrip(input: input)
            if report.status == "unsupported" {
                throw XCTSkip("Signed ARM64 roundtrip requires ARM64; no execution claimed")
            }
            XCTAssertEqual(report.status, "passed", report.detail)
            XCTAssertEqual(report.result, UInt64(input) * 4 + 18)
            XCTAssertTrue(report.callbackExecuted)
            XCTAssertTrue(report.tlsPreserved)
            XCTAssertTrue(report.canariesPreserved)
            XCTAssertTrue(report.stackPreserved)
            XCTAssertTrue(report.registerCanariesPreserved)
            XCTAssertFalse(report.ilp32EntryProven, "Full-pointer signed stub never proves guest entry32")
        }
    }

    func testLowMemoryRoundtripSeparatelyWhenMappingIsAvailable() throws {
        let report = ProbeRunner.run(input: 11)
        if report.status == "unavailable" || report.status == "unsupported" {
            throw XCTSkip(report.detail + "; low-memory device behavior remains unproven")
        }
        XCTAssertEqual(report.status, "passed", report.detail)
        XCTAssertEqual(report.result, 62)
        XCTAssertTrue(report.callbackExecuted)
        XCTAssertTrue(LowAddressRange.isValid(address: report.dataAddress, byteCount: report.pageSize))
        XCTAssertTrue(report.context32Proven)
        XCTAssertFalse(report.ilp32EntryProven)
    }
}
