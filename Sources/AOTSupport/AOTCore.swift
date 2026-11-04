import Foundation
import CryptoKit
import CAOTEngine

public struct AOTReport: Codable, Sendable {
    public let status: String
    public let detail: String
    public let message: String
    public let steps: UInt32
    public let programCounter: UInt64
    public let faultAddress: UInt64
    public let hostArena: UInt64
    public let hostCalls: UInt32
    public let slot: UInt32?
    public let stubInstructions: UInt32
    public let relocationCount: Int
    public let imageLoadedFromELF: Bool
    public let imagePreparation: String
    public let snapshotSHA256: String
    public let guestSHA256: String
    public let sourceCommit: String
    public let nativeArchitecture: String
    public let jitUsed: Bool
    public let originalGuestMachineCodeExecuted: Bool
}

private struct ImageMetadata: Decodable {
    let snapshotSHA256: String
    let guestSHA256: String
    let imageEnd: UInt32
    let relocationCount: Int
    let generation: String
    let commit: String
}

public enum AOTRunner {
    public static func run(heapBase: UInt32 = 0x0490_0000, heapSize: UInt32 = 0x0010_0000) throws -> AOTReport {
        guard let metadataURL = Bundle.module.url(forResource: "ImageMetadata", withExtension: "json"),
              let imageURL = Bundle.module.url(forResource: "VMImage", withExtension: "bin") else {
            throw NSError(domain: "AOTImage", code: 1, userInfo: [NSLocalizedDescriptionKey: "Generated AOT resources are missing"])
        }
        let metadata = try JSONDecoder().decode(ImageMetadata.self, from: Data(contentsOf: metadataURL))
        let image = try Data(contentsOf: imageURL)
        let digest = SHA256.hash(data: image).map { String(format: "%02x", $0) }.joined()
        guard digest == metadata.snapshotSHA256 else {
            throw NSError(domain: "AOTImage", code: 2, userInfo: [NSLocalizedDescriptionKey: "Snapshot identity mismatch"])
        }
        var measured = BO2AOTResult()
        _ = image.withUnsafeBytes { bytes in
            bo2_aot_run(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, metadata.imageEnd, heapBase, heapSize, &measured)
        }
        let detail = withUnsafePointer(to: &measured.detail) { String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)) }
        let message = withUnsafePointer(to: &measured.message) { String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)) }
        let status = measured.status == 6 ? "host_call" : measured.status == 1 ? "invalid_layout" : "stopped"
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "other"
        #endif
        return AOTReport(status: status, detail: detail, message: message, steps: measured.steps,
            programCounter: measured.pc, faultAddress: measured.fault, hostArena: measured.host_arena,
            hostCalls: measured.host_calls, slot: measured.slot == UInt32.max ? nil : measured.slot,
            stubInstructions: measured.stub_instructions, relocationCount: metadata.relocationCount,
            imageLoadedFromELF: true, imagePreparation: metadata.generation,
            snapshotSHA256: digest, guestSHA256: metadata.guestSHA256, sourceCommit: metadata.commit,
            nativeArchitecture: architecture, jitUsed: false, originalGuestMachineCodeExecuted: false)
    }
}
