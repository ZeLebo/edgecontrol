# EdgeControl

EdgeControl is a macOS menu bar app for controlling volume, built-in display brightness, and media playback from the edges of the built-in trackpad.

Slide one finger along an enabled edge. The cursor stays in place while the gesture is active. A compact on-screen symbol and level bar show the accepted value. Use the menu bar icon to open Settings, pause control, or quit.

## Controls

Each of the four edges has its own action:

- **Volume** or **Brightness:** choose Absolute or Relative adjustment.
- **Track Navigation:** slide right or up for the next track, left or down for the previous track.
- **Seek:** slide right or up to skip forward 10 seconds, left or down to skip backward 10 seconds.
- **Disabled:** leave the edge available for ordinary trackpad use.

Absolute adjustment maps the full trackpad width or height to 0% through 100%. Relative adjustment starts from the current system level, regardless of the initial touch position. At 1x sensitivity, movement across the trackpad changes a level by 100 percentage points. Sensitivity is adjustable from 0.25x to 3x for Relative, Track Navigation, and Seek.

Media gestures send one command after deliberate movement; lift your finger before sending another. The current media player must support the requested command. Haptic feedback can be turned off in Settings. Edge width is adjustable from 3% to 15%.

The default assignments are Volume on the bottom edge and Brightness on the right edge. Both use Absolute adjustment. Changes are saved automatically. Settings from the previous prototype are imported once without changing the original record.

## Build and run

Requires an Apple silicon Mac, macOS 14 or later, and Xcode with the macOS SDK.

```sh
./scripts/build-app.sh
open build/EdgeControl.app
```

Grant Accessibility access when requested so EdgeControl can hold the cursor still during control gestures. Resume from the menu after granting access. Pause, sleep, lock, an extra finger, or leaving the edge ends control.

The app uses macOS private APIs for built-in trackpad input, built-in display brightness, and media commands. Support can change between macOS releases. External trackpads and external display brightness are outside this version's scope.

## Verify

```sh
swift test
```

Tests use synthetic contacts and pure command mappings. They do not change system volume or brightness, send media commands, or generate haptics.

```sh
.build/release/EdgeControl --diagnose
```

Diagnostic mode reports contacts and shows feedback without changing levels or sending commands. It still requires Accessibility access for cursor capture.

```sh
.build/release/EdgeControl --render-previews build/previews
```

Preview mode renders Settings and feedback images without starting trackpad input or changing system outputs.
