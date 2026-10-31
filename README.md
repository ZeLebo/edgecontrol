# EdgeControl v1.0

A native macOS menu bar app for absolute volume control along the bottom edge of the built-in trackpad.

Slide one finger inside the bottom 5% of the trackpad. Left means 0%, centre 50%, right 100%. A stationary touch does not change volume. The cursor stays still during adjustment. Lift all fingers before the next gesture.

## Build

Requires macOS, an Apple Silicon Mac with a built-in trackpad, and Swift 6.2 or newer.

```sh
swift test
./scripts/build-app.sh
open build/EdgeControl.app
```

Grant Accessibility from the menu and select Resume. Pause and Quit are available from the menu bar. A device without adjustable system volume is reported as unsupported.

## Implementation

Uses AppKit, CoreAudio, CoreGraphics and the private MultitouchSupport framework. There are no third-party dependencies. The local build is ad-hoc signed, not notarized. Private APIs may change after a macOS update.

Automated tests do not capture live input or change system volume. Build outputs stay outside source control.
