# Opt-in Harmony device verification

This evaluation host consumes the built HAR and production public ArkTS wrappers.
It is not a Kotlin/ArkTS asynchronous bridge and is not device-validated merely
because CI compiles it. Native smoke remains independently runnable with no network.

## Before running

Use an already authorized device/emulator and toolchain. Do not interpret the
API18 package configuration as proof that the bundled native libraries load on API18.
Install/sign only through an authorized existing setup; this guide grants no new
agreement, signing or distribution permission. Never upload keys or credentials.
The example app requests INTERNET permission. No network request or Preferences
file is opened automatically: the new actions require explicit button presses.

## Controlled network fixture

On a computer you control, run a fresh dedicated fixture:

```sh
python3 tools/http_fixture.py --tls
```

It listens on loopback HTTP port 18082 and untrusted TLS port 18443.
Use an explicitly configured device-to-host tunnel/port mapping for BOTH ports,
or an equivalent isolated controlled fixture implementing these routes. Verify
the direction for your installed hdc version: a host-to-device mapping alone is
not sufficient. Do not expose this test server to the public Internet.
The TLS fixture remains self-signed and MUST NOT be installed in any trust store.

Enter the device-reachable HTTP and HTTPS origins including ports in the app.
Fields start empty. Only explicit loopback/private IPv4 origins are accepted;
no hostname, public target, credentials, path or implicit default is permitted.
Addresses alone do not establish ownership: use only your own dedicated endpoint.
The fixture's TLS certificate may not match a remapped address. This is still an
untrusted-certificate negative test, not an isolated hostname-validation test.
No certificate validation override is provided.

Press “Run controlled network tests”. Success requires:
- fixture body hello and preserved HTTP 400;
- HTTP 302 returned, fresh redirect target counter remains zero;
- chunked response cap rejection and slow request timeout;
- TLS ready, an increased TLS accepted-connection counter, zero TLS HTTP hits,
  and the expected Io failure without changing system trust;
- a successful subsequent HTTP request.

Only NETWORK_DEVICE_PASS is a pass. A missing/failure marker, unreachable server,
wrong counters or timeout is NOT a pass. Stop other fixture clients and restart
the fixture between trials. Retain app result, fixture evidence, device/OS,
toolchain, HAR/commit identifiers and mapping used. These tests do not prove all
TLS scenarios, resource reclamation, process shutdown races or memory stability.
HTTP is explicitly enabled only for these controlled test calls.

## Preferences process-restart check

Use a fresh non-secret lowercase alphanumeric/hyphen token of 8–32 characters.
Press “Prepare storage restart test”. It creates, reads and updates a Unicode
value using PreferencesStringStore through NamespacedStringStore, then awaits
flush acknowledgement in the dedicated madcore_device_verification file.

After STORAGE_PREPARED, force-stop the app process WITHOUT clearing app data or
uninstalling. Relaunch and enter exactly the same token; press “Verify storage
after process restart”. The same-process attempt is rejected. Verification reads
the expected persisted value, removes only that token's test key, checks absence,
and awaits flush. Only STORAGE_RESTART_DEVICE_PASS is success. Document actual
process termination/relaunch; this manual protocol is not an automated proof of
a restart. A missing token must fail, never reinitialize itself.

No unrelated preferences are enumerated or cleared. Interrupted preparations
leave only their own test key; rerun verification after a process restart using
that token to remove it. The test is not crash/power-loss durability, multi-process
consistency or encryption verification. Do not use real application data.

## Build evidence vs execution

Existing Harmony CI copies this consumer outside the checkout, supplies the
built HAR, and assembles an unsigned HAP. Referencing the harness from the real
page checks API18 compilation but executes none of these actions.
Do not replace a device run with mocked ETS tests or a green assembly job.

## Dual toolchain pins and device compatibility preflight

The source baseline inspected for this note is
`08daa1b248c82d29cbca8c873752398dd64d86c4`.

- ArkTS/HAP: both build-profile files declare targetSdkVersion and
  compatibleSdkVersion `5.1.0(18)`; compileSdkVersion is not explicitly set.
  The build uses SHA-checked CLI `5.1.0.840` with the recorded SDK
  `5.1.0.125/API18` and Hvigor `5.18.5`.
- Native: the Kotlin fork is `2.2.21-1.0.0`. The NAPI build explicitly selects
  `cpf-llvm-19-x86_64-linux-dev-20` and
  `sysroot-ohos-aarch64-6.0.2.640-04`. It links against that sysroot's libraries,
  not the API18 CLI's native sysroot. Both generated libraries are AArch64.
- Huawei's [6.0.2 developer-suite mapping](https://developer.huawei.com/consumer/en/doc/harmonyos-releases/overview-602/)
  maps DevEco Studio `6.0.2.640` to HarmonyOS `6.0.2(22)` and SDK
  `6.0.2.130/API22`. This supports the suite-version association, not proof of
  the CPF repackaged sysroot's complete provenance, or this binary's minimum API.

These are **different build inputs**, not one uniformly verified API18 toolchain.
A newer sysroot does not alone prove API22 is required, and a compatibleSdkVersion
declaration does not prove API18 suffices. Native imported libraries/symbols and
the actual device loader determine whether the package can load.
Do not change the declared minimum, add weak-symbol workarounds or upgrade tools
merely to conceal a load failure.

Before a device trial, record the exact device OS/API from its About screen,
CPU/application ABI, HDC and SDK versions, source commit and rebuilt HAP/SO hashes.
Require arm64-v8a support; an x86_64-only emulator cannot validate these SOs.
Preserve `readelf -h`, `readelf -d`, `readelf --dyn-syms --wide` and
`readelf --relocs --wide` output for both SOs, plus the existing native inventory.
Check DT_NEEDED dependencies and undefined imports against the chosen device's
available system libraries/API declarations. Weak imports alone are not a safety
proof; verify guarded use as well. Keep diagnostics limited to this test app and
its load attempt; do not collect unrelated app logs or credentials.

Run native smoke first. On install/load failure, preserve the app-scoped loader
error and missing-library/symbol names, then stop network/storage checks.
A failure is a compatibility finding, not a harness pass. One newer-device pass
would establish only that tested device/API, not a lower supported minimum.
No device run or minimum-runtime certification has occurred.
