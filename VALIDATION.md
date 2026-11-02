# Validation of the diagnostic experiment

This document records evidence for the synthetic probe, not for Black Ops II execution. No game binaries or assets are in this repository.

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
