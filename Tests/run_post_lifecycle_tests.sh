#!/bin/bash
set -euo pipefail

test_root=$(cd "$(dirname "$0")/.." && pwd)
test_build=$(mktemp -d "${TMPDIR:-/tmp}/inkwell-post-tests.XXXXXX")
trap 'rm -rf "$test_build"' EXIT

xcrun clang -fobjc-arc -fmodules -fmodules-cache-path="$test_build/modules" \
	-framework Cocoa -framework WebKit -framework QuartzCore -framework AVFoundation \
	-I "$test_root/Source" -I "$test_root/Shared/RSCore" \
	"$test_root/Tests/post_lifecycle_test.m" \
	"$test_root/Source/MBNewPostController.m" "$test_root/Source/MBPreviewButton.m" \
	"$test_root/Source/MBMainController.m" "$test_root/Source/MBAppDelegate.m" \
	"$test_root/Source/MBClient.m" "$test_root/Source/MBSessionController.m" \
	"$test_root/Source/MBAuthController.m" "$test_root/Source/MBEntry.m" \
	"$test_root/Source/MBHighlight.m" "$test_root/Source/MBSubscription.m" \
	"$test_root/Source/MBPodcastController.m" "$test_root/Source/MBPodcastChapter.m" \
	"$test_root/Source/MBPodcastContainerView.m" \
	"$test_root/Source/MBPodcastSlider.m" "$test_root/Source/MBPodcastArtworkButton.m" \
	"$test_root/Source/MBPodcastPassthroughView.m" "$test_root/Source/MBPodcastPassthroughImageView.m" \
	"$test_root"/Shared/MMMarkdown/*.m \
	-o "$test_build/post_lifecycle_test"

"$test_build/post_lifecycle_test"
