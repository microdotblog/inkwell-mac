#!/bin/bash
set -euo pipefail

test_root=$(cd "$(dirname "$0")/.." && pwd)
test_build=$(mktemp -d "${TMPDIR:-/tmp}/inkwell-sidebar-tests.XXXXXX")
trap 'rm -rf "$test_build"' EXIT

xcrun clang -fobjc-arc -fmodules -fmodules-cache-path="$test_build/modules" \
	-framework Cocoa -framework QuartzCore \
	-I "$test_root/Source" \
	"$test_root/Tests/sidebar_selection_test.m" \
	"$test_root/Source/MBClient.m" "$test_root/Source/MBSessionController.m" \
	"$test_root/Source/MBEntry.m" "$test_root/Source/MBMention.m" \
	"$test_root/Source/MBSubscription.m" "$test_root/Source/MBHighlight.m" \
	"$test_root/Source/MBRoundedImageView.m" "$test_root/Source/MBConversationCellView.m" \
	"$test_root/Source/MBSidebarController.m" "$test_root/Source/MBSidebarTableView.m" \
	"$test_root/Source/MBSidebarRowView.m" "$test_root/Source/MBSidebarCell.m" \
	"$test_root/Source/MBSidebarRecapBoxView.m" "$test_root/Source/NSStrings+Extras.m" \
	"$test_root"/Shared/MMMarkdown/*.m \
	-o "$test_build/sidebar_selection_test"

"$test_build/sidebar_selection_test"
