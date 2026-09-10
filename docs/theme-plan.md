# Theme Plan — Liquid Glass + System / Dark / Light

## Where things stand today

- **Appearance row is a placeholder.** `SettingsPages.swift:22-24` shows
  static text "Follows system", and `SettingsView.swift:72` hardcodes
  `.preferredColorScheme(.dark)` — the app is dark-only regardless of the
  system setting.
- **Model only knows gradients.** `AppearanceSettings`
  (`Models.swift:135-159`) has `gradientIndex`, messages, sound — no theme
  mode, no material style.
- **Glass look already exists informally.** Break overlay pills use
  `.ultraThinMaterial` (`BreakViews.swift:114`); backdrop is wallpaper +
  `blur(60)` + veil/vignette (`:47-60`). Menu-bar popup and all settings
  views hardcode dark colors (`.white` text, `laBG/laSide/laCard`), ~100
  sites.
- **Toolchain allows real Liquid Glass.** `build.sh` targets `macosx13.0`
  but compiles against the 26 SDK, so SwiftUI's Tahoe `glassEffect` can be
  used behind `if #available(macOS 26, *)` with a 13–15 fallback. No
  build-system change needed.

## Proposed design

1. **Model** — extend `AppearanceSettings` (auto-persisted via the existing
   `SettingsStore` snapshot; defaults preserve current behavior):
   - `AppTheme: system | dark | light` (default `.system`)
   - `BreakMaterial: frosted | liquidGlass` (default `.frosted`, today's look)
2. **Settings UI**
   - General → replace the placeholder with a System/Dark/Light segmented
     picker, id `settings.general.appTheme` (+ `.value` label for
     `axdrive read`).
   - Customize Screen → add Material picker (Frosted / Liquid Glass) with
     live gradient-preview cards, id
     `settings.customizeScreen.material`.
3. **Theming engine**
   - Replace forced `.dark` with
     `.preferredColorScheme(settings.appearance.appTheme.colorScheme)`
     (`nil` = system) at the Settings root and menu-bar popup root.
   - Introduce adaptive tokens (e.g. `laPrimaryText`, `laSecondaryText`,
     adaptive `laBG/laSide/laCard`) and migrate hardcoded `.white` /
     `white.opacity` text and dark card fills onto them. This migration is
     the bulk of the work.
   - Break overlay **stays dark cinematic** in all modes (white text over
     blurred wallpaper is a readability requirement, not a theme bug) —
     theme affects Settings + popup; the overlay only gains the material
     choice.
4. **Liquid Glass rendering**
   - Tahoe+: `glassEffect` on pills / countdown / heads-up card; pre-26:
     existing `.ultraThinMaterial` fallback. Same code path,
     availability-gated, so 13.x users see no regression.
   - Out of scope (per README parity stance): animated backgrounds
     (Slipstream, Fireflies-style) stay out; this is a material upgrade,
     not motion.
5. **A11y interaction** — Reduce Transparency forces the opaque fallback
   even on Tahoe; Increase Contrast deepens strokes/veil. (Ties into parity
   plan item #8.)
6. **Tests** (per AGENTS.md): `./build.sh` → picker ids drivable via
   `axdrive click/read` → persistence test (set Light + Liquid Glass,
   relaunch without `--reset-state`, assert retained) → full
   `scripts/test-*.sh` suite + `axdrive terminate`.

## Effort sketch

- Picker + model + plumbing: small.
- Light-mode color migration across Settings/MenuBar: medium (wide but
  mechanical).
- Liquid Glass gated material: small.

Suggested slice order: settings + popup theming (Batch 1) → Glass material
→ full light-mode migration.

## Addendum — the Translucent theme (v2)

A fourth `AppTheme` case, `.translucent`, was added after the original three
shipped. It is a *chrome* theme rather than a palette: the app stays dark and
lets the desktop show through its own windows, the look of a wallpaper reading
through a dark editor.

- **Model** — `AppearanceSettings.AppTheme.translucent`; `colorScheme` maps it
  to `.dark`, `usesVibrancy` is true only for it. Old snapshots are unaffected
  (`.system` remains the default).
- **Surfaces** — `Theme.swift` owns `ThemeSurface` (`window` / `sidebar` /
  `popup`). `themedSurface(_:theme:reduceTransparency:)` paints either the
  existing opaque token (`laBG` / `laSide` / `laPopup`) or an
  `NSVisualEffectView` backdrop (`.underWindowBackground` / `.sidebar` /
  `.hudWindow`) under a black scrim (0.38 / 0.48 / 0.34) that holds text
  contrast over a bright wallpaper.
- **Window chrome** — vibrancy only reaches the desktop if the host window is
  non-opaque, so `themedChrome(theme:reduceTransparency:configuresWindow:)`
  flips `isOpaque` / `backgroundColor` / `titlebarAppearsTransparent` on the
  settings `NSWindow` and pins it to `darkAqua` (these windows are built by
  `WindowManager`, and `preferredColorScheme` does not reach them). It restores
  only what it changed, so the other three themes are untouched. The menu-bar
  popover and the automation sheet pass `configuresWindow: false` — the popover
  owns its own window and arrow, and stacked see-through layers just read as
  one blur.
- **Cards** — `cardSurface(cornerRadius:)` replaces the direct `laCard` fills;
  over vibrancy it uses a stronger wash plus a hairline edge so cards still
  separate from the wallpaper. It reads the `laTranslucentSurfaces`
  environment flag set by `themedChrome`.
- **Break overlay** — unchanged. It was already dark cinematic in every theme.
- **A11y** — Reduce Transparency falls back to the opaque dark fills, matching
  the Liquid Glass rule in item 5 above.
