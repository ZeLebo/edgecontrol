# Changelog

Release dates are shown in UTC. Download app archives and SHA256 checksums from the linked releases.

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
