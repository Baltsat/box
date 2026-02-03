#!/usr/bin/env bun

/**
 * Additional macOS defaults that nix-darwin can't set
 * Run via: bun script/macos.ts
 */

const { $ } = Bun;

// Chrome browser shortcuts
const browser_shortcuts = async (bundle_id: string) => {
  await $`defaults write ${bundle_id} NSUserKeyEquivalents -dict-add "Duplicate Tab" '@$d'`
    .quiet()
    .nothrow();
  await $`defaults write ${bundle_id} NSUserKeyEquivalents -dict-add "New Tab to the Right" '@t'`
    .quiet()
    .nothrow();
  await $`defaults write ${bundle_id} NSUserKeyEquivalents -dict-add "Bookmark All Tabs..." '@$b'`
    .quiet()
    .nothrow();
};

console.log('[macos] configuring Chrome shortcuts...');
await browser_shortcuts('com.google.Chrome');

const chrome_running = (await $`pgrep -i chrome`.quiet().nothrow()).exitCode === 0;
if (chrome_running) {
  console.log('[macos] ⚠️  Chrome running, shortcuts apply after restart');
}

// Trackpad settings
console.log('[macos] configuring trackpad...');
await $`defaults write -g "com.apple.trackpad.scaling" -float 2.0`.quiet();
await $`defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true`.quiet();
// 3-finger tap = look up dictionary
await $`defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerTapGesture -int 2`.quiet();
// 3-finger vertical swipe = app exposé
await $`defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerVertSwipeGesture -int 2`.quiet();
// App exposé gesture enabled
await $`defaults write com.apple.dock showAppExposeGestureEnabled -bool true`.quiet();

// Accessibility zoom (pinch to zoom anywhere)
console.log('[macos] configuring accessibility zoom...');
await $`defaults write com.apple.universalaccess closeViewTrackpadGestureZoomEnabled -bool true`.quiet();
await $`defaults write com.apple.universalaccess closeViewPanningMode -int 0`.quiet();
await $`defaults write com.apple.universalaccess closeViewZoomScreenShareEnabledKey -bool true`.quiet();
await $`defaults write com.apple.universalaccess closeViewSmoothImages -bool false`.quiet();

// Disable bottom-left hot corner (Quick Notes is annoying)
console.log('[macos] disabling bottom-left hot corner...');
await $`defaults write com.apple.dock wvous-bl-corner -int 1`.quiet();
await $`defaults write com.apple.dock wvous-bl-modifier -int 0`.quiet();

// NOTE: Not disabling Spotlight Cmd+Space — user uses it for input switching

// Activate settings
console.log('[macos] activating settings...');
await $`/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u`
  .quiet()
  .nothrow();

console.log('[macos] done ✓');
