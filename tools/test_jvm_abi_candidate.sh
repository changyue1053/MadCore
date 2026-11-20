#!/usr/bin/env bash
# Compatibility entry point for the standalone JVM candidate.
set -euo pipefail
exec bash "$(dirname "${BASH_SOURCE[0]}")/test_abi_candidate.sh" jvm
