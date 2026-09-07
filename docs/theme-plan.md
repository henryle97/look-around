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
