# Native bridge host simulation

`bash tools/test_native_bridge.sh` compiles the actual production
`harmony/native/madcore_napi.c` into a test translation unit against a small fake
NAPI header/implementation and stub MadCore C functions. No production file is
rewritten. Fake types and behavior are not evidence of Huawei ABI compatibility.

Coverage: constructor module registration, exported method descriptors, ABI and
64-bit time values, argument count/type errors, NAPI query/conversion failures,
length mismatch, empty input, exactly 65,536 bytes and oversize rejection,
embedded NUL preservation with explicit byte length, native negative result,
true/false results, and result/export creation failures. Assertions stay enabled.

AddressSanitizer and UndefinedBehaviorSanitizer are required. LeakSanitizer is on
by default. In a ptrace-controlled environment where LeakSanitizer cannot run,
use `ASAN_OPTIONS=detect_leaks=0:halt_on_error=1 bash tools/test_native_bridge.sh`
and report that leak checking was not performed. Do not describe this fallback
as a complete sanitizer pass. CI should use the default whenever supported.

Not covered: actual Harmony NAPI/runtime, actual Kotlin implementations, malloc
failure injection, real JS string conversion semantics, or device behavior.
The fake SDK never performs JSON validation; it records bytes and returns a
controlled native result. It must not be packaged into the HAR/HAP.
