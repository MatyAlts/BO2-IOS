# BO2 iOS runtime feasibility probe

This repository contains an independent diagnostic experiment. It does not contain or run Black Ops II, Requiem, proprietary game assets, APKs, ELF guests, or a playable launcher.

The app measures a prerequisite for a possible future port: guarded mappings and a synthetic signed ARM64 callback roundtrip. The signed entry and callback use full64-bit function pointers. A low32-bit context token is checked separately when a low mapping exists. Success does **not** prove an executable ILP32 guest entry, the original engine ABI/TLS, or rendering compatibility.

## Launch correction: Control 0.2.0 (2)

The original IPA used `__PAGEZERO=0x4000` and placed `__TEXT` at `0x4000`. Both target devices were reported to exit before any screen after installation through iLoader. That layout conflicts with the conservative arm64 loader contract in [Apple's published XNU loader](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/mach_loader.c): ordinary arm64 executables are checked for a hard pagezero covering 4 GiB. The exact termination reason on the reported OS versions still needs a device crash report; it is not established as an iOS/iPadOS version incompatibility or an iLoader defect.

**Use `RuntimeProbe-Control-0.2.0-unsigned.ipa`, not the original reduced-layout IPA.** Control restores the toolchain's standard layout, has the distinct display name `Runtime Probe Control` and bundle identifier `dev.maty.bo2runtimeprobe.control`, and runs no native experiment automatically. The low-memory button is expected to report unavailable under the standard protected window. A successful launch does not establish a way to execute the BO2 guest below 4 GiB.

The user confirmed Control 0.2.0 launches on both target devices: the signed baseline passed and low-memory allocation was unavailable. The [Control build and artifact](https://github.com/MatyAlts/BO2-IOS/actions/runs/41514486873) also passed actual app launch/relaunch UI tests and binary-layout checks. See [VALIDATION.md](VALIDATION.md) for the evidence and remaining limits.

## Safety and scope

- Memory is reserved with non-replacing mmap hints; every returned address is checked. No MAP_FIXED or unmapping of host-owned regions.
- Data and stack are RW, guard pages remain inaccessible. No unsigned executable memory or JIT code runs.
- The assembly adapter preserves its touched callee-saved registers and the original stack. It never writes x18 or TPIDR_EL0. Synthetic register canaries and pthread-specific state are checked.
- A signed full-pointer baseline runs independently of low-memory availability, including in ARM64 CI. A skipped low-memory test is reported as unproven.
- The device executable uses standard arm64 `__PAGEZERO` and `__TEXT` placement. Regression tests inspect the actual IPA bytes, not only build settings. The reduced-layout variant is no longer produced.
- All memory mappings created by a run are released. Addresses in reports are historical measurements, not live handles.

## Build and install

The GitHub Actions workflow tests the Swift package on a standard macOS runner, tests iOS Simulator, actually launches and relaunches the app in UI tests, archives an unsigned device app, and packages `RuntimeProbe-Control-0.2.0-unsigned.ipa`. The IPA requires appropriate signing for the user's chosen sideload method. No signing credentials or developer certificate are included.

Local macOS: install XcodeGen, run `swift test`, `xcodegen generate`, then use the `RuntimeProbe` scheme. Minimum deployment iOS18. Simulator tests and successful builds do not replace measurements on iPhone/iPad.

The UI runs an experiment only when its button is pressed. Signed baseline and low-memory experiment are separate. Guest execution and executable-memory/JIT results remain explicitly unproven.
