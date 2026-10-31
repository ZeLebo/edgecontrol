# EdgeControl v1.2.0

Control volume and built-in display brightness from the edges of the built-in trackpad.

The bottom 5% controls volume from left to right. The right 5% controls brightness from bottom to top. Slide to set an absolute level from 0% to 100%. A stationary touch does not change a level. The cursor stays still during adjustment.

Open Settings from the menu bar to assign Volume, Brightness or Disabled to each of the four edges and adjust the active strip width from 3% to 15%. Settings save automatically.

## Build

Requires macOS 14 or newer, an Apple Silicon Mac with a built-in trackpad, and Swift 6.2 or newer.

```sh
swift test
./scripts/build-app.sh
open build/EdgeControl.app
```

Grant Accessibility from the menu and select Resume. Pause and Quit are available from the menu bar.

Run `build/EdgeControl.app/Contents/MacOS/EdgeControl --diagnose` to inspect gesture targets without changing system levels.

## Implementation

Uses AppKit, CoreAudio, CoreGraphics and the private MultitouchSupport and DisplayServices frameworks. There are no third-party dependencies. The local build is ad-hoc signed, not notarized. Private APIs may change after a macOS update. Unsupported outputs are reported in the menu.

Automated tests do not capture live input or change system levels. Build outputs stay outside source control.
