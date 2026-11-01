# EdgeControl

Control volume, display and keyboard brightness, media playback, and keyboard shortcuts with gestures along your Mac's built-in trackpad edges. EdgeControl is a native Swift and AppKit menu bar app with no third-party dependencies.

[Download the latest release](https://github.com/ZeLebo/edgecontrol/releases/latest) · [Changelog](CHANGELOG.md)

## Install and run

Requires an Apple silicon Mac with a built-in trackpad and macOS 14 or later.

1. Download the `arm64.zip` archive from [Releases](https://github.com/ZeLebo/edgecontrol/releases/latest) and extract it.
2. Open `EdgeControl.app`. Quit any older running copy before opening an update.
3. Grant Accessibility access when prompted, then choose **Resume** from the menu bar if needed.

The menu bar icon provides **Settings**, **Pause / Resume**, and **Quit**. Release builds are ad hoc signed and are not notarized. If macOS blocks a downloaded copy, you can build the app locally.

## Default controls

| Location | Gesture | Action |
| --- | --- | --- |
| Bottom edge | Slide left or right | Set volume from 0% to 100% |
| Right edge | Slide down or up | Set built-in display brightness from 0% to 100% |
| Bottom-left or bottom-right corner | Double tap | Mute / unmute |

The active strip starts at 5% of the trackpad's width or height. Touching an edge alone does not change a level. Start sliding one finger along the strip to adjust it; the pointer stays still while the slide is active. Lifting the finger, leaving the strip, or adding another finger ends the gesture.

## Profiles

Use the profile picker in Settings or the menu bar to switch between Everyday and Media. Create, duplicate, rename, or delete profiles to keep separate edge assignments, modes, sensitivity, and tap actions. Switching profiles preserves the current system levels.

Choose a **Profile Switch** point in Settings to cycle profiles with a double tap. This point is shared by every profile and takes priority over its ordinary tap action. The original action is preserved underneath. Leave the switch unassigned to use only the menu and profile picker. A short HUD shows the selected profile.

Existing settings become the Everyday profile on update. The Media preset adds track navigation and seeking.

## Customize gestures

Open **Settings** and select any of the four edges. Assign **Volume**, **Brightness**, **Keyboard Backlight**, **Track Navigation**, **Seek**, **Keyboard Shortcut**, or **Disabled**. Edge width is adjustable from 3% to 15%.

For volume, display brightness, and keyboard backlight, choose a mode separately for each edge:

- **Absolute:** the finger's position selects the level, with reachable 0% and 100% endpoints.
- **Relative:** movement adjusts the current system level without jumping to the initial touch position. Sensitivity ranges from 0.25x to 3x. At 1x, moving across 10% of the trackpad adds or subtracts 10 percentage points.

**Track Navigation** sends Previous / Next Track. **Seek** skips backward or forward by 10 seconds. Right or up moves forward; left or down moves backward. Each slide sends one command. Lift and slide again to repeat. Sensitivity also applies to media slides.

### Precision with Shift

Hold Shift while sliding for movement at one fifth of the normal sensitivity. For an Absolute level action, Shift temporarily adjusts relative to the current level. Once engaged, relative adjustment lasts until the finger lifts, so releasing Shift restores normal speed without jumping back to the absolute position. The next gesture uses the configured mode again.

### Double taps

There are eight points: four shared corners and the middle of each edge. A corner has one action shared by its two edges.

Click a point on the diagram or select it in the point picker. Choose **None**, **Mute / Unmute**, **Play / Pause**, **Previous Track**, **Next Track**, or a backward / forward 10-second skip. Purple points have an action assigned. Center points start unassigned.

Keyboard Backlight also provides an On / Off tap action. It restores the last known nonzero level; if no previous level is known, it starts at 50%. System automatic brightness and idle dimming keep their existing settings.

### Keyboard shortcuts

Choose **Keyboard Shortcut** as an edge's Slide Action to assign separate shortcuts to Left / Down and Right / Up. Choose the same action for a double-tap point to assign its shortcut. Bindings belong to the selected profile; the global Profile Switch point remains shared.

Click a shortcut button to record a key combination, or choose F13 through F24 and the Command, Option, Control, and Shift modifiers. Recording uses the focused field in the editor. Some system combinations are reserved by macOS.

Configure the matching shortcut in the target application. A gesture sends one press and release through the macOS keyboard event stream; the receiving app decides how to handle it. F13 through F20 use native virtual key codes. F21 through F24 use function-character events and are app-dependent: some apps and global hotkey tools do not recognize them. The editor shows this compatibility note for those keys.

For example, create a profile for your recorder, assign a recording hotkey to a corner, and switch to that profile with the shared Profile Switch point. A short HUD identifies the new profile.

### Visual and haptic feedback

A compact icon and bar show level changes without visible text or percentages. Media and mute actions show a short symbol indicator.

Haptic strength follows the current volume, display brightness, or keyboard backlight level:

| Level | Feedback |
| --- | --- |
| 0% to 33% | Weak |
| 34% to 66% | Medium |
| 67% to 100% | Strong |

Media and double-tap actions use a medium pulse. Turn **Haptic Feedback** off in Settings to disable it.

Settings save automatically. Earlier assignments are imported on update. If two old actions share a corner, a configured horizontal-edge action takes priority; otherwise the vertical-edge action is kept.

## Launch at login

Enable **Launch at Login** in **General…** to start EdgeControl when you log in. The checkbox reads the macOS registration state. If approval is required, the status points to System Settings > General > Login Items. Building, testing, or opening Settings does not register the app automatically.

## Application exclusions

Open **General…** in Settings to choose apps where gestures should pause. Exclusions apply to every profile. Switching to another app resumes gestures after a full finger lift; manual Pause remains independent. Only app bundle identifiers are stored in preferences.

## Compatibility

Volume requires an audio output with writable system volume. Brightness controls the built-in display. External trackpads and external display brightness are outside the current scope. Media commands and seeking depend on the active player. Haptic feedback requires a supported actuator on the selected built-in trackpad; transport errors appear in the menu while the controls remain available.

Background touch input, device-specific haptics, display and keyboard brightness, and media commands use private Apple frameworks. A macOS update can change their behavior. No driver or background service is installed.

## Build from source

Select an Xcode toolchain with Swift 6.2 or later, then run:

```sh
xcrun swift test
./scripts/build-app.sh
open build/EdgeControl.app
```

The build script creates an ad hoc signed app. Tests use synthetic input and recording transports; they do not change system outputs or generate physical haptics.

To inspect contacts and gesture targets without changing levels or sending commands, quit the regular instance and run:

```sh
build/EdgeControl.app/Contents/MacOS/EdgeControl --diagnose
```

Diagnostic mode still requires Accessibility for pointer capture.

## Source checks

The public tree contains application source, tests, source assets, build tools, this README, and the changelog. Local notes, agent files, preferences, caches, and build outputs stay outside Git.

```sh
python3 scripts/audit-public-tree.py
python3 scripts/audit-public-tree.py --head
python3 scripts/audit-public-tree.py --history
```

These inspect the index, the latest commit, and all reachable commits and tag identities respectively. The audit rejects files outside the public allowlist, machine paths, email addresses in source, common access tokens, and private keys. Commit and tag identities must use a GitHub noreply address.
