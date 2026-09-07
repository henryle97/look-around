# Parity Plan — LookAway changelog vs LookAround

Source: `Parity Backlog` artifact (LookAway public changelog v0.9 → v2.4.5,
Oct 2023 – Sep 2026, condensed to distinct capabilities), checked against
`Sources/LookAround` at commit `cc13fdf`.

Status at survey time: 26 built, 2 partial, 6 not built, 5 out of scope.
Two backlog claims were outdated on re-check (noted below).

## Survey

### Break engine & scheduling
| # | Feature | Status | Evidence |
|---|---------|--------|----------|
| 1a | Daily snooze / postpone limit | Built | `Models.swift:25,189-190` (`snoozesPerDay=5`, `snoozesUsedToday`); `BreakScheduler.swift:92-139` (guard + `consumeSnooze()` + daily reset); enforced in `BreakViews.swift:246-256`, `MenuBarView.swift:65-70` |
| 1b | Per-session / per-break-cycle snooze cap | Not built | No `snoozesUsedThisCycle` counter; all 5 daily snoozes can burn on one break |
| 1c | Skip / Pause consume budget | Not built | `advanceSkip():150-155` and `pauseWork(for:167-172)` bypass the snooze budget |
| 2 | Away-time as quiet toast + undo | Not built (greenfield) | Backlog says "full heads-up panel", actually silent: `BreakScheduler.swift:290-307` freezes timer, counts `naturalBreaks/minutes`. No toast view exists (`BreakViews.swift` has only PreBreak/FloatingCountdown/OvertimePill), no `WindowManager` away window |

### Triggering & control
| # | Feature | Status | Evidence |
|---|---------|--------|----------|
| 3 | System-wide keyboard shortcuts | Partial (display-only) | `SettingsPages2.swift:602-638` lists ⌃⌥⌘B/S/Z, self-admits "work while panel is open". No `RegisterEventHotKey`, no global event tap, no `commands {}` in `LookAroundApp.swift:41-51`. Only local Esc monitor (`WindowManager.swift:51`) |
| 4 | Inbound AppleScript dictionary | Partial (outbound-only) | Outbound via `AutomationRunner.swift:6-47`, fired at `BreakScheduler.swift:428,462`. No `.sdef`, no scripting keys in `Info.plist:1-36`, no script command handlers |

### Stats & Screen Score
| # | Feature | Status | Evidence |
|---|---------|--------|----------|
| 5 | Per-app usage breakdown | Not built | `Models.swift:183-197` tracks one `screenTimeTodayMinutes` total; `BreakScheduler.swift:252-255,326-327` probes frontmost app per-tick then discards; `ActivityProbe.swift:42-56` transient only |
| 6 | Website usage stats | Not built (zero implementation) | No `website|domain|browser|URL` hits in `Sources/`; needs extension/history-parsing + consent — biggest privacy lift |
| 7 | Longest session without break / median session | Not built | No duration log; `BreakStats` has counts + streak only; `beginBreak/endBreak:375-463` never records work-segment length |

### Accessibility
| # | Feature | Status | Evidence |
|---|---------|--------|----------|
| 8 | VoiceOver labels, keyboard nav, Reduce Motion / Contrast / Color | Not built | Only axdrive test IDs exist (`SettingsView.swift:73,135,288`, `MenuBarView.swift:34,87`). No `accessibilityLabel/Hint`, no `keyEquivalent`/focus management, no motion/transparency/contrast reads — `blur(60)` in `BreakViews.swift:47` unconditional |

Out of scope (per README, not planned): Focus Filters, custom image/audio
uploads + animated backgrounds, iPhone/iPad sync + Live Activities,
licensing/seats, multi-language localization.

## Plan

### Batch 1 — quick wins
- **1b+1c. Per-session snooze cap + close bypasses.** Add
  `snoozesUsedThisCycle` to `BreakStats`, reset in `beginBreak/endBreak`,
  guard in `snoozePreBreak/snoozeBreakScreen`. Decision needed: Skip
  consumes 1, Pause gets its own daily cap. Settings: `maxSnoozesPerBreak`
  ChipStepper (`settings.screenBreaks.maxPerBreak`). Accept: burn cap on one
  break → controls disable + "No snoozes left".
- **7. Session lengths.** Stamp `workSegmentStart` at `endBreak`, push
  duration at `beginBreak` into capped `workDurations[]` (500), compute
  max/median in `BreakStats`, show two rows in `MenuBarView` + Stats page,
  include in reset. No permissions needed.
- **2. Away toast + undo.** New `AwayToastView` + `WindowManager` floating
  window; snapshot `nextBreakAt` before freeze, Undo restores + subtracts
  `naturalBreakMinutes`. Identifier `away.toast(.undo)`. Accept: idle >60s →
  toast; Undo → timer restored.
- **8. A11y pass.** Labels on overlay/pills/ring/menu rows,
  `keyEquivalent(.defaultAction)` + focus order on PreBreak, gate
  blur/vignette/animation on `accessibilityReduceMotion/Transparency` +
  high-contrast variants. Reuse existing `*.accessibilityIdentifier`
  convention.

### Batch 2 — medium
- **3. Global hotkeys.** `CGEvent` tap or Carbon `RegisterEventHotKey`,
  user-remappable storage in `SettingsStore`, enable toggle + conflict
  alert, fallback message if Accessibility denied. Must handle background
  firing + `axdrive` regression.
- **4. Inbound scripting.** `LookAround.sdef` (`start break`, `snooze`,
  `pause/resume`, `stats`), `Info.plist` scripting keys, `NSScriptCommand`
  handlers thin over `BreakScheduler`. Docs + TCC note.
- **5. Per-app breakdown.** `NSWorkspace.didActivateApplication`
  accumulator `[bundleID: seconds]`, persisted daily, top-5 UI in Stats,
  privacy toggle + "exclude app" list. Builds on idle/pause attribution
  already in `BreakScheduler`.

### Batch 3 — hard / reconsider
- **6. Website stats.** Recommend scoping down to "browser-app time" (free
  from Batch 2's per-app data) or defer — true per-domain needs extension
  or history-file parsing (Safari/Chrome SQLite, Full Disk Access, consent
  UI). If pursued: opt-in only, domain aggregation, no URLs stored.

Suggested order: 1b+1c → 7 → 2 → 8 → 3 → 4 → 5 → 6 (decision point).

## Per-feature test contract (AGENTS.md)

`./build.sh` → stable `accessibilityIdentifier` → `--ui-testing
--reset-state` launch → extend `scripts/test-*.sh` (follow break-duration
template) → full suite `for f in scripts/test-*.sh; do $f || break; done` →
`axdrive terminate` (never leave `LookAround` running). Respect the 400ms
`SettingsStore` debounce in persistence asserts.
