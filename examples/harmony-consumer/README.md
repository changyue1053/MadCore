# Independent MadCore HAR consumer (unsigned build probe)

This directory is a standalone Stage application. It imports only the packaged
`madcore` HAR, not the MadCore source tree or the original application.

## Intended toolchain

- Official Linux CLI 5.1.0.840, SDK 5.1.0.125 / API 18, Hvigor 5.18.5.
- Project modelVersion 5.0.0; HarmonyOS product target/compatible API 18.
- Use the bundle's configured SDK, Node, ohpm and Hvigor. This sample does not
  download tools, accept licenses or configure credentials.

## Build after the library's HAR job passes

Copy the produced HAR to `libs/madcore.har`. Do not create a placeholder archive.
Run from this directory with the authorized toolchain on PATH:

```sh
test -s libs/madcore.har
ohpm install --all
hvigorw assembleHap --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon
```

Expected unsigned output: `entry/build/default/outputs/default/entry-default-unsigned.hap`.
No signing configuration, certificates, account or network permission is supplied.
No `local.properties` or developer-machine paths are committed.

## Verification limits

The project has passed pinned-SDK unsigned HAP assembly in CI, but has not been device-run. API 18 here is a build probe
setting, not a certified minimum version for the CPF native runtime. A successful
HAP build proves archive consumption/ArkTS compilation/packaging, not native load
or ABI compatibility. Inspect the HAP for all transitive native libraries.

After separate authorized signing and installation, the page invokes `abiVersion`
and time/JSON calls through the imported HAR. `NativeSmoke.ets` requires 11 cases:
ABI 1, sane epoch, ASCII/Unicode JSON, rejection of malformed/array/null/empty/NUL
input, exactly 64 KiB UTF-8 accepted, and 64 KiB + 1 rejected. The UI reports success only after
those calls execute. Missing-library failures at module import may stop the page
before its try/catch; device launch logs remain necessary. This app includes no
native `.so` stub or replacement and cannot make absent native code appear to pass.

The host must provide a compatible arm64 libc++_shared.so. CI uses the approved SDK runtime only in its ephemeral unsigned test app; no runtime redistribution or release permission is inferred.
