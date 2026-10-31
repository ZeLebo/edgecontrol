# EdgeControl v1.4.0

Control volume and built-in display brightness from the edges of the built-in trackpad.

The bottom 5% controls volume from left to right. The right 5% controls brightness from bottom to top. Slide to set an absolute level from 0% to 100%. A stationary touch does not change a level. The cursor stays still during adjustment.

Open Settings from the menu bar to assign Volume, Brightness or Disabled to each of the four edges and adjust the active strip width from 3% to 15%. Choose Absolute or Relative separately for each edge. Absolute maps the touch position to 0% through 100%. Relative starts from the current system level, regardless of where the finger lands; movement adds or subtracts percentage points. Sensitivity ranges from 0.25x to 3x and applies only in Relative mode. Settings save automatically.

A compact floating indicator shows an icon and a monochrome level bar. It has no visible title or percentage. The bar draws the latest level directly without progress-control interpolation. The application icon is generated from the source PNG during the build.

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
