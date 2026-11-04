# BO2 iOS runtime feasibility probe

This repository contains the source of an independent diagnostic experiment. Control 0.3.0 adds a finite signed-AOT Multiplayer initialization path through the first logging import. It is a partial bootstrap experiment, not a playable game.

The repository commits only original tooling, the decoder/emitter, bridge, Swift UI and tests. At build time, `Tools/AOT/prepare.py` downloads the official T6Requiem 2.1.0-beta APK from its upstream release, verifies its SHA256 and the Multiplayer guest SHA256, and derives a finite native C translation plus an 80 MiB data snapshot. APKs, ELF files, generated instruction source and snapshots remain in ignored directories. The compiled diagnostic artifact contains the derived initialization experiment.

The snapshot preparation copies the real ELF PT_LOAD bytes, zero-fills BSS and applies 135,795 P32 relative relocations at build time with logical bias zero. The app verifies the snapshot hash, creates a fresh high-address host arena, constructs a limited boot/table/stack fixture and executes the compiled translation. The original guest instruction bytes are not executed as ARM64 machine code. Guest addresses are virtual numbers; neither guest TLS instructions nor JIT execute in this first-host experiment.

The app measures a prerequisite for a possible future port: guarded mappings and a synthetic signed ARM64 callback roundtrip. The signed entry and callback use full64-bit function pointers. A low32-bit context token is checked separately when a low mapping exists. Success does **not** prove an executable ILP32 guest entry, the original engine ABI/TLS, or rendering compatibility.

## Launch correction: Control 0.2.0 (2)

The original IPA used `__PAGEZERO=0x4000` and placed `__TEXT` at `0x4000`. Both target devices were reported to exit before any screen after installation through iLoader. That layout conflicts with the conservative arm64 loader contract in [Apple's published XNU loader](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/mach_loader.c): ordinary arm64 executables are checked for a hard pagezero covering 4 GiB. The exact termination reason on the reported OS versions still needs a device crash report; it is not established as an iOS/iPadOS version incompatibility or an iLoader defect.

Control 0.2.0 replaced the original reduced-layout IPA with the toolchain's standard layout and bundle identifier `dev.maty.bo2runtimeprobe.control`. Control 0.3.0 retains that identifier and layout. Experiments run manually. The low-memory button is expected to report unavailable under the standard protected window. A successful launch does not establish a way to execute the BO2 guest below 4 GiB.

The user confirmed Control 0.2.0 launches on both target devices: the signed baseline passed and low-memory allocation was unavailable. The [Control build and artifact](https://github.com/MatyAlts/BO2-IOS/actions/runs/41514486873) also passed actual app launch/relaunch UI tests and binary-layout checks. See [VALIDATION.md](VALIDATION.md) for the evidence and remaining limits.

## Safety and scope

- Memory is reserved with non-replacing mmap hints; every returned address is checked. No MAP_FIXED or unmapping of host-owned regions.
- Data and stack are RW, guard pages remain inaccessible. No unsigned executable memory or JIT code runs.
- The assembly adapter preserves its touched callee-saved registers and the original stack. It never writes x18 or TPIDR_EL0. Synthetic register canaries and pthread-specific state are checked.
- A signed full-pointer baseline runs independently of low-memory availability, including in ARM64 CI. A skipped low-memory test is reported as unproven.
- The device executable uses standard arm64 `__PAGEZERO` and `__TEXT` placement. Regression tests inspect the actual IPA bytes, not only build settings. The reduced-layout variant is no longer produced.
- All memory mappings created by a run are released. Addresses in reports are historical measurements, not live handles.
- The finite AOT path uses an 80 MiB checked flat guest arena and logical null guard. It does not yet implement all guest mapping holes, segment permissions or the complete engine ABI.

## Build and install

The GitHub Actions workflow tests the Swift package on a standard macOS runner, tests iOS Simulator, launches and relaunches the app and invokes its manual AOT action in UI tests, archives an unsigned device app, and packages `RuntimeProbe-Control-0.3.0-unsigned.ipa`. The IPA requires appropriate signing for the user's chosen sideload method. No signing credentials or developer certificate are included.

Local macOS: install XcodeGen, run `python3 Tools/AOT/prepare.py`, then `swift test` and `xcodegen generate`, and use the `RuntimeProbe` scheme. Preparation is required on a clean clone because generated Swift/C targets and resources are deliberately not in git. `AOT_APK_PATH` may select an existing local APK; the exact same hash checks still apply. Minimum deployment iOS18. Simulator tests and successful builds do not replace measurements on iPhone/iPad.

The UI runs an experiment only when its button is pressed. The new **Run signed MP AOT bootstrap** button runs the translated finite initialization path, then reports the actual message, logical PC, instruction count, source commit and image hashes. It should reach slot 0 logging with `[nx-mem] guest arena 04900000..04a00000 (1 MB)` and a newline. The runtime stops at that host boundary; host return, subsequent engine initialization, rendering, audio, network and playable MP/Zombies remain outside this artifact.

Signed synthetic baseline and low-memory experiments remain separate. JIT is unused and untested by the AOT path. The executable keeps the standard 4 GiB PAGEZERO verified by the binary regression tests. The same control bundle identifier is retained, version 0.3.0 build 3.
