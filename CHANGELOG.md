# Changelog

Release dates are shown in UTC. Download app archives and SHA256 checksums from the linked releases.

## [2.5.2](https://github.com/ZeLebo/edgecontrol/releases/tag/v2.5.2) (2026-11-04)

- Allow edge widths down to 1% for slides and double taps, with 1% steps in Settings.

## [2.5.1](https://github.com/ZeLebo/edgecontrol/releases/tag/v2.5.1) (2026-11-04)

- Keep gestures running when the audio output cannot control volume or mute. Show the audio error in the menu, release the cursor, and allow a new gesture to use a supported output after a device switch.

## [2.5.0](https://github.com/ZeLebo/edgecontrol/releases/tag/v2.5) (2026-11-01)

- Assign per-profile keyboard shortcuts to double-tap points and both directions of an edge slide.
- Record combinations locally or choose F13 through F24 with Command, Option, Control, and Shift modifiers.
- Use native key codes for F13 through F20 and explicitly marked, app-dependent function-character events for F21 through F24.
- Preserve the click-suppression tail after a profile switch, even when the new recognizer receives empty frames.
- Send paired key events with a short hold; release owned keys on cancellation and restore physical modifier flags. Pause gestures while editing modal settings.

## [2.4.0](https://github.com/ZeLebo/edgecontrol/releases/tag/v2.4) (2026-11-01)

- Add native Launch at Login control in General Settings, using the actual macOS registration state.
- Show when system approval is still required. Register or unregister only when the user changes the checkbox.

## [2.3.0](https://github.com/ZeLebo/edgecontrol/releases/tag/v2.3) (2026-11-01)

- Add a global app exclusion list in General Settings, selected with the native app picker.
- Pause input and release the pointer in excluded apps; resume requiring a full finger lift while preserving manual Pause.
- Store bundle identifiers only and preserve earlier profile records.

## [2.2.0](https://github.com/ZeLebo/edgecontrol/releases/tag/v2.2) (2026-11-01)

- Hold Shift for five times finer movement, including relative levels and media gestures.
- Temporarily adjust Absolute levels relatively while using precision; keep the current gesture relative until lift to avoid jumps when Shift is released.

## [2.1.0](https://github.com/ZeLebo/edgecontrol/releases/tag/v2.1) (2026-11-01)

- Add built-in keyboard backlight control with Absolute / Relative adjustment, sensitivity, and haptic feedback.
- Add On / Off double tap with restoration of the last known nonzero level.
- Preserve system automatic brightness and idle dimming settings; report unsupported keyboards or rejected writes.

## [2.0.0](https://github.com/ZeLebo/edgecontrol/releases/tag/v2.0) (2026-11-01)

- Add named profiles with create, duplicate, rename, delete, and manual selection in Settings and the menu bar.
- Add a user-selectable global double-tap point for cycling profiles, preserving the point's per-profile action underneath.
- Show the active profile in the menu and a short HUD. Preserve current system levels when switching.
- Import existing settings into Everyday and provide a second Media preset.

## [1.9.0](https://github.com/ZeLebo/edgecontrol/releases/tag/v1.9) (2026-11-01)

- Use one device-specific haptic path for volume, brightness, media, and double-tap actions.
- Scale volume and brightness feedback with the current level: weak at 0% to 33%, medium at 34% to 66%, strong at 67% to 100%. Discrete actions use medium feedback.
- Show haptic transport errors in the menu while keeping the controls available.

## [1.8.0](https://github.com/ZeLebo/edgecontrol/releases/tag/v1.8) (2026-11-01)

- Replace duplicate edge endpoints with eight double-tap points: four shared corners and four edge centers.
- Select a point on the Settings diagram or in the native point picker.
- Migrate earlier settings while preserving edge assignments, modes, and sensitivity. A configured horizontal action takes priority when old corner actions conflict; otherwise the vertical action is kept.

## [1.7.0](https://github.com/ZeLebo/edgecontrol/releases/tag/v1.7) (2026-10-31)

- Add configurable double-tap actions at edge endpoints: mute, play / pause, previous / next track, and backward / forward 10-second skips.
- Mark configured tap zones in Settings and preserve preferences from earlier versions.

## [1.6.0](https://github.com/ZeLebo/edgecontrol/releases/tag/v1.6) (2026-10-31)

- Add Previous / Next Track and backward / forward 10-second seek gestures.
- Send one media command per slide, with per-edge sensitivity.

## [1.5.0](https://github.com/ZeLebo/edgecontrol/releases/tag/v1.5) (2026-10-31)

- Add optional haptic feedback, a Settings switch, and a pulse rate limit.

## [1.4.0](https://github.com/ZeLebo/edgecontrol/releases/tag/v1.4) (2026-10-31)

- Add separate Absolute / Relative modes and 0.25x to 3x sensitivity for each edge.
- Start relative adjustment from the current system level, preserving small movements and immediate reversal at the limits.

## [1.3.1](https://github.com/ZeLebo/edgecontrol/releases/tag/v1.3.1) (2026-10-31)

- Replace the HUD with a compact icon and monochrome bar, without visible text or percentages.
- Draw the latest level directly to remove progress interpolation lag.

## [1.3.0](https://github.com/ZeLebo/edgecontrol/releases/tag/v1.3) (2026-10-31)

- Add an on-screen level indicator and an application icon.

## [1.2.0](https://github.com/ZeLebo/edgecontrol/releases/tag/v1.2) (2026-10-31)

- Add an English settings window, assignments for all four edges, adjustable strip width, and saved preferences.

## [1.1.0](https://github.com/ZeLebo/edgecontrol/releases/tag/v1.1) (2026-10-31)

- Add absolute brightness control along the right edge of the built-in trackpad.

## [1.0.0](https://github.com/ZeLebo/edgecontrol/releases/tag/v1.0) (2026-10-31)

- Add absolute bottom-edge volume control with reachable 0% and 100% endpoints.
- Hold the pointer still during an active slide and provide menu bar controls for Pause / Resume and Quit.
