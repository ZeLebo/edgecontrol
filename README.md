# EdgeControl

Control volume, display brightness, and media playback from the edges of the built-in trackpad. EdgeControl is a native Swift and AppKit menu bar app with no third-party dependencies.

## Use

Open the app and grant Accessibility access when prompted. The menu bar icon opens Settings and provides Pause, Resume, and Quit.

By default, the bottom 5% of the trackpad controls volume and the right 5% controls built-in display brightness. Start moving one finger along an edge to adjust its level. Touching the edge alone does not change the level. The pointer stays still during an active slide. Lifting the finger, leaving the strip, or adding another finger ends the gesture.

In Settings, select any of the four edges and choose its controls:

- **Absolute:** position selects the level, with reachable 0% and 100% endpoints.
- **Relative:** movement adds to or subtracts from the current system level. Touching at a different position does not cause a jump. Sensitivity is separate for each edge, from 0.25x to 3x.
- **Track Navigation / Seek:** a slide sends Previous or Next Track, or skips backward or forward by 10 seconds. Each slide sends one command; lift and slide again to repeat. Right or up moves forward.
- **Double tap:** eight points cover the four corners and the middle of each edge. A corner has one action shared by its two edges. Select a point on the diagram or in the point picker, then choose None, Mute / Unmute, Play / Pause, Previous Track, Next Track, or a 10-second skip. Purple points mark configured actions. The two bottom corners toggle mute by default.
- **Feedback:** a compact icon and bar show level changes. Volume and brightness use weak haptics at 0% to 33%, medium at 34% to 66%, and strong at 67% to 100%. Media and double-tap actions use a medium pulse. Haptic feedback can be turned off. Edge width is adjustable from 3% to 15%.

Settings are saved automatically. Existing assignments are imported once from earlier formats. If two old actions share a corner, a configured horizontal-edge action takes priority; otherwise the vertical-edge action is kept. Center points start unassigned.

## Build

Requires an Apple silicon Mac with a built-in trackpad, macOS 14 or later, and a selected Xcode toolchain with Swift 6.2 or later.

```sh
xcrun swift test
./scripts/build-app.sh
open build/EdgeControl.app
```

The script creates an ad hoc signed app. Release downloads are also ad hoc signed and are not notarized; building locally is an option if macOS blocks a download.

To inspect trackpad coordinates without changing levels or sending media commands:

```sh
build/EdgeControl.app/Contents/MacOS/EdgeControl --diagnose
```

Diagnostic mode still uses the input and pointer capture permissions. Quit the regular instance before running another copy.

## Compatibility

Volume requires an audio output with writable system volume. Brightness controls the built-in display. External trackpads and external display brightness are outside the current scope. Media commands depend on the active player, and seek support varies by player. Haptic feedback requires a supported actuator on the selected built-in trackpad. Transport errors appear in the menu; level and media controls remain available.

Background touch input, device-specific haptics, display brightness, and media commands use private Apple frameworks. A macOS update can change their behavior. No driver, entitled host process, or background service is installed.

## Source and releases

The repository includes application source, tests, the source icon, and build tools. Local notes, agent files, preferences, caches, and build outputs are excluded by a source allowlist.

Before a commit, run `python3 scripts/audit-public-tree.py` to inspect the Git index. Use `--head` for the latest commit or `--history` for all reachable commits and tags. The audit rejects files outside the allowlist, machine paths, email addresses in source, common access tokens, private keys, and Git identities without a GitHub noreply address.

The history starts with a README-only commit. Functional stages have their own tags, starting with volume control in `v1.0`. Commit and tag dates record when those stages were committed; they are not backdated.
