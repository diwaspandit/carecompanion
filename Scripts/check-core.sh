#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
CORE_CHECK_DIR=$(mktemp -d /tmp/carecompanion-smoke.XXXXXX)
trap 'rm -rf "$CORE_CHECK_DIR"' EXIT
swiftc -swift-version 6 -module-cache-path /tmp/carecompanion-clang -parse-as-library Sources/CareCore/*.swift Scripts/CoreSmoke.swift -o "$CORE_CHECK_DIR/core-smoke"
"$CORE_CHECK_DIR/core-smoke"
