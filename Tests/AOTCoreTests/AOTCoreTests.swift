import XCTest
import AOTCore

final class AOTCoreTests: XCTestCase {
    func testRealGuestImageFormatsTwoDifferentHeaps() throws {
        let inputs: [(UInt32, UInt32, String)] = [
            (0x0490_0000, 0x0010_0000, "[nx-mem] guest arena 04900000..04a00000 (1 MB)\n"),
            (0x0490_0000, 0x0020_0000, "[nx-mem] guest arena 04900000..04b00000 (2 MB)\n")
        ]
        for (base, size, expected) in inputs {
            let report = try AOTRunner.run(heapBase: base, heapSize: size)
            XCTAssertEqual(report.status, "host_call", report.detail)
            XCTAssertEqual(report.message, expected)
            XCTAssertEqual(report.slot, 0)
            XCTAssertEqual(report.hostCalls, 1)
            XCTAssertEqual(report.stubInstructions, 4)
            XCTAssertEqual(report.relocationCount, 135_795)
            XCTAssertTrue(report.imageLoadedFromELF)
            XCTAssertGreaterThan(report.steps, 37)
            XCTAssertGreaterThan(report.hostArena, UInt64(UInt32.max))
            XCTAssertFalse(report.jitUsed)
            XCTAssertFalse(report.originalGuestMachineCodeExecuted)
        }
    }

    func testHeapOverlappingActualImageIsRejected() throws {
        let report = try AOTRunner.run(heapBase: 0x0480_0000, heapSize: 0x0010_0000)
        XCTAssertEqual(report.status, "invalid_layout")
        XCTAssertEqual(report.hostCalls, 0)
        XCTAssertEqual(report.steps, 0)
        XCTAssertTrue(report.detail.contains("overlap"))
    }
}
