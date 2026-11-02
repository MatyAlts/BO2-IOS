# BO2 iOS runtime feasibility probe

This repository contains an independent diagnostic experiment. It does not contain or run Black Ops II, Requiem, proprietary game assets, APKs, ELF guests, or a playable launcher.

The app measures a prerequisite for a possible future port: guarded writable mappings below4GB and a synthetic signed ARM64 callback roundtrip. The signed entry and callback use full64-bit function pointers. A low32-bit context token is checked separately. Success does **not** prove an executable ILP32 guest entry, the original engine ABI/TLS, or rendering compatibility.

## Safety and scope

- Memory is reserved with non-replacing mmap hints; every returned address is checked. No MAP_FIXED or unmapping of host-owned regions.
- Data and stack are RW, guard pages remain inaccessible. No unsigned executable memory or JIT code runs.
- The assembly adapter preserves its touched callee-saved registers and the original stack. It never writes x18 or TPIDR_EL0. Synthetic register canaries and pthread-specific state are checked.
- A signed full-pointer baseline runs independently of low-memory availability, including in ARM64 CI. A skipped low-memory test is reported as unproven.
- The device executable requests a reduced __PAGEZERO solely as an experiment. The linker output must be inspected; acceptance by the actual iOS loader remains a device test.
- All memory mappings created by a run are released. Addresses in reports are historical measurements, not live handles.

## Build and install

The GitHub Actions workflow tests the Swift package on a standard macOS runner, tests iOS Simulator, archives an unsigned device app, and packages `RuntimeProbe-unsigned.ipa`. The IPA requires appropriate signing for the user's chosen sideload method. No signing credentials or developer certificate are included.

Local macOS: install XcodeGen, run `swift test`, `xcodegen generate`, then use the `RuntimeProbe` scheme. Minimum deployment iOS18. Simulator tests and successful builds do not replace measurements on iPhone/iPad.

The UI runs an experiment only when its button is pressed. Signed baseline and low-memory experiment are separate. Guest execution and executable-memory/JIT results remain explicitly unproven.
