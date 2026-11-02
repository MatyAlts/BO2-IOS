# Validation of the diagnostic experiment

This document records evidence for the synthetic probe, not for Black Ops II execution. No game binaries or assets are in this repository.

## Launch failure follow-up: Control 0.2.0 (2)

The user reported immediate exit before the first screen on both physical devices after installation through iLoader. The original artifact was confirmed to contain `__PAGEZERO` size `0x4000` and `__TEXT` address `0x4000`. The published [XNU arm64 loader](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/mach_loader.c) requires a hard pagezero covering 4 GiB when the check is enforced. This is a concrete layout defect relative to the standard arm64 contract, and a very likely explanation; without an `.ips` report it is not a confirmed device termination diagnosis.

- Safety net and RED: [run41514258957](https://github.com/MatyAlts/BO2-IOS/actions/runs/41514258957), commit `61fa49b`: existing Swift tests passed (six passed, one low-memory skip); two new actual-IPA regression tests then failed on the original layout. No native code or production configuration had been changed yet.
- Fix: commit `de99260` removes the device-only reduced-pagezero linker flag. Bundle identifier, display name and version distinguish the new control from a cached or previously installed IPA.
- New artifact tests parse actual Mach-O load commands from the zipped device executable and require standard pagezero/text placement.
- New UI test launches the app twice and verifies the idle screen remains in the foreground without running either experiment. Previous unit tests did not establish that the application itself launched.
- Native probe code is unchanged. JIT does not run at startup and is unrelated to this startup regression.

Final GREEN: [run41514486873](https://github.com/MatyAlts/BO2-IOS/actions/runs/41514486873), code commit `de99260`: Swift package seven tests (six passed, one low-memory skip), iOS unit suite seven tests (six passed, one low-memory skip), and one UI test passed. The UI test actually launched and relaunched the application, verified both idle buttons, and checked that the process did not immediately terminate. Both device-IPA binary layout regression tests passed. The unsigned archive and packaging succeeded.

Control metadata was read from the archived Info.plist: display name `Runtime Probe Control`, bundle identifier `dev.maty.bo2runtimeprobe.control`, version `0.2.0`, build `2`, minimum OS `18.0`. The direct dylib commands inventoried by `otool -L` reference system frameworks and `/usr/lib` libraries; no direct non-system dependency was missing from the unsigned archive. This does not audit an IPA after a sideload tool re-signs it.

The user subsequently confirmed the shared reports were from **Runtime Probe Control 0.2.0**: the app launched on both physical devices, the signed baseline passed, and the low-memory experiment was unavailable. These are user-supplied physical results, separate from CI evidence. They support the standard-layout correction, but do not identify the exact previous crash termination reason without an `.ips` report. They do not prove low-address guest execution or JIT compatibility.

| Task | Test File | Layer | Safety Net | RED | GREEN | TRIANGULATE | REFACTOR |
|---|---|---|---|---|---|---|---|
| Standard device load layout | `Tests/ArtifactTests/test_standard_ipa.py` | Actual-IPA regression | Existing six pass, one skip | Both tests failed on original IPA before config edit, run41514258957 | Both passed on Control IPA, run41514486873 | Pagezero coverage and text placement independently checked | None; native code unchanged |
| Actual app launch | `Tests/LaunchUITests/LaunchUITests.swift` | iOS UI integration | Existing unit suite unchanged | Added before fix; binary regression above captured failing startup layout | UI launch/relaunch passed, run41514486873 | First launch and relaunch, idle controls and process survival | None |

[Control IPA and logs](https://github.com/MatyAlts/BO2-IOS/actions/runs/41514486873/artifacts/13175337930): `RuntimeProbe-Control-0.2.0-unsigned.ipa`, 27,644 bytes, SHA256 `f0a7d2e532ed9e6d2ec595a7d22d0ce8c52cdb52099cfa85753caefedb160c48`. This supersedes the historical artifact below. Documentation-only changes after `de99260` do not change the built IPA.

The original IPA and the original execution records below are historical. The original reduced-layout IPA should not be installed for the next comparison.

## Executed results

- RED: [run41512012663](https://github.com/MatyAlts/BO2-IOS/actions/runs/41512012663), commit `b34eb2e`, failed while compiling the real XCTest source with `no such module 'ProbeCore'`. Production code had not been written. An earlier scaffold-only run failed on a manifest platform spelling and is **not** counted as behavioral RED.
- Initial GREEN: [run41512415213](https://github.com/MatyAlts/BO2-IOS/actions/runs/41512415213), commit `f267931`: macOS ARM64, seven tests, six passed, one explicitly skipped, zero failures. The signed assembly roundtrip actually executed for inputs1 and7.
- Final GREEN/build: [run41512717021](https://github.com/MatyAlts/BO2-IOS/actions/runs/41512717021), commit `6892273`: macOS package tests and iOS Simulator XCTest each ran seven tests, six passed, one skipped, zero failures. Device archive and unsigned IPA packaging succeeded.
- The skipped test is specifically low-memory allocation: `ENOMEM`, with no callback executed. It remains a device acceptance item and is not counted as a passing low-memory experiment.
- The device Mach-O's `__PAGEZERO` was inspected with `otool` and its size asserted to be `0x4000`. The simulator executable did not receive this linker option. Device loader acceptance has not been tested.

## TDD Cycle Evidence

All tests are in `Tests/ProbeCoreTests/ProbeCoreTests.swift`. Safety net is N/A because this was a new isolated project with no existing production files or tests.

| Task | Test File | Layer | Safety Net | RED | GREEN | TRIANGULATE | REFACTOR |
|---|---|---|---|---|---|---|---|
| Low-address range and measured-result policy | `Tests/ProbeCoreTests/ProbeCoreTests.swift` | Unit | N/A, new project | Executed, missing ProbeCore module | Passed on macOS and iOS Simulator | Last representable byte; null/empty/crossing/overflow; correct/wrong callback result and changed TLS | Test renamed to describe its limited policy; final run passed |
| Signed callback, stack, registers and thread state | same | Native integration | N/A, new project | Tests existed before native implementation | Actual signed ARM64 roundtrip passed on both CI platforms | Distinct inputs1/7 give22/46, callback executes, stack/TLS/register/data canaries checked | No behavioral refactor |
| Low-memory callback acceptance | same | Conditional native integration | N/A, new project | Test written before native implementation | Explicitly skipped in both CI environments, not passed | Separate from signed baseline; device test still required | None |

The pure policy helper covers only its declared memory/callback/canary/TLS/result inputs. The authoritative native result additionally requires stack and register checks; the helper is not used as a substitute for those checks.

## Artifact

[Unsigned IPA and verification logs](https://github.com/MatyAlts/BO2-IOS/actions/runs/41512717021/artifacts/13173279954)

`RuntimeProbe-unsigned.ipa`, SHA256:

```text
0ca05381dde833b68de6c9ce6afc47e9abc30dd3569af7cdaa44d7dd331d334d
```

The artifact requires signing for the selected sideload method. It contains a diagnostic app, not the game. It has no JIT entitlement and does not execute unsigned memory. CI success does not prove the game ABI, guest entry32, guest TLS/gateways, rendering, or compatibility with either target physical device.

On-device next step: install a properly signed copy, run the signed baseline, then the low-memory experiment, and retain the shared report from each device. A failed launch after the reduced PAGEZERO layout is itself an unresolved loader result, not proof that the memory experiment ran.
