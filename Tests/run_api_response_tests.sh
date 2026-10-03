#!/bin/bash
set -euo pipefail

test_root=$(cd "$(dirname "$0")/.." && pwd)
test_build=$(mktemp -d "${TMPDIR:-/tmp}/inkwell-api-tests.XXXXXX")
trap 'rm -rf "$test_build"' EXIT

xcrun clang -fobjc-arc -fmodules -fmodules-cache-path="$test_build/modules" \
	-framework Cocoa \
	-I "$test_root/Source" -I "$test_root/Shared/RSCore" \
	"$test_root/Tests/api_response_test.m" \
	"$test_root/Source/MBClient.m" \
	"$test_root/Source/MBAppDelegate.m" \
	"$test_root/Source/MBSessionController.m" \
	"$test_root/Source/MBSubscription.m" \
	"$test_root/Source/MBHighlight.m" \
	"$test_root"/Shared/MMMarkdown/*.m \
	-o "$test_build/api_response_test"

"$test_build/api_response_test"
