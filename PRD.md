# TilePilot (GUI for yabai/skhd) - Product Requirements Document (v1.2)

## Document Control
- Version: 1.2
- Date: 2026-02-26
- Status: Active development (foundation shipped, major product cycle replanned)
- Platform: macOS (direct distribution, non-App-Store)

---

## 1) Product Summary

TilePilot is a native macOS menu bar app that adds a click-first control layer on top of `yabai` and `skhd`.
It improves observability, reliability, and ease of use without replacing the underlying window manager engine.

### North Star
- Keep `yabai/skhd` as the engine.
- Enable click-first operation and gradual shortcut learning.
- Never fake state when `yabai` is degraded, incompatible, or uncertain.

### Strategy Note (v1.2)
- Foundation/recovery work is largely built and should be treated as a shipped baseline.
- The next major cycle should prioritize finishing product workflows (especially Actions) and improving discoverability/usability for powerful features.
- Continue reducing jargon/noise in user-facing surfaces; show internals only when useful.
- Keep capability detection and recovery logic as infrastructure, not the product "headline."

---

## 1.1) Implementation Snapshot (As Built vs Planned)

### Completed / Mostly Implemented
- Native menu bar app shell + main window (`TilePilot`) with left-click/right-click split.
- Capability/health checks, setup checks, diagnostics export, command log.
- Fresh Mac dependency bootstrap flow (Homebrew / `yabai` / `skhd`) via Terminal installer helper.
- Live `yabai` polling + degraded mode/fallback view.
- Window behavior controls:
  - global default (float-by-default vs auto-tile)
  - hover focus (`focus_follows_mouse`)
  - per-app `Never Tile` / `Always Tile`
  - managed `yabairc` section + backups
- Focused window runtime actions (tile/float/toggle).
- Shortcut viewer (`skhdrc` parsing) and safe `skhdrc` managed-section editor.
- Developer packaging flow:
  - `/Applications/TilePilot.app`
  - hi-res icon bundled
  - Developer ID signing supported

### Partially Implemented / Needs Product Finish
- **Actions tab**: foundational actions and gating exist, but catalog/organization/copy/discoverability are incomplete.
- **Quick access menu**: improved and simplified, but still needs long-term curation and context-aware entries.
- **Main view (`TilePilot`)**: live map exists, but "find a window / act on it quickly" workflows are still weak.
- **Health / Setup / Config surfaces**: powerful, but some wording/information architecture still reflects internal build history.

### Not Yet Implemented (High-Value Next Cycle)
- Visual explainers/onboarding for advanced features (one concept at a time).
- Strong "feature discovery" UX tied to real user problems ("Why do my windows move?" / "How do I keep this app floating?").
- Finished `Actions` product experience (grouping, labels, macros, learnability, quick access integration).
- Better search/filter/focus workflows in the main `TilePilot` view.

---

## 2) Problem Statement

Current `yabai/skhd` users face:
- Hard-to-memorize shortcuts.
- Invisible or ambiguous WM state.
- Unclear recovery when permissions/services degrade.
- Setup drift after macOS updates or version mismatches.
- Fear of editing config files directly.

TilePilot addresses this with:
- Live state visibility.
- Clickable common actions.
- Searchable shortcut reference.
- Health + compatibility diagnostics with guided recovery.
- Safe, reversible config editing for known-safe sections.

---

## 3) Goals and Non-Goals

## Goals (v1)
- Operate core workflows without shortcut memorization.
- Provide trustworthy live state and health/capability status.
- Detect common setup and compatibility blockers early (permissions, Mission Control, scripting-addition constraints).
- Clearly communicate degraded mode and limit risky actions.
- Make essential config edits safe and reversible.
- Keep UI responsive even during command failures/recovery.
- Make advanced `yabai` features teachable through progressive, visual explainers.
- Prefer user language (desktops/windows/actions) over engine jargon in primary surfaces.

## Non-Goals (v1)
- Full parser/editor for all `skhd` grammar.
- Full graphical rule engine for all `yabai` rule flags.
- Exact grid tiling guarantees beyond engine limits.
- Full drag-and-drop workspace designer.
- Automatic repair of SIP/scripting-addition constraints beyond guided steps.

---

## 4) Priority Profiles (Subject to User Priorities)

The product should support different build order priorities without changing the core architecture.

### A. Support-Load Reduction First (Default v1.1 Plan)
- Build Doctor/capability detection, setup checklist, recovery UX, and diagnostics export before advanced actions.

### B. New-User Adoption First
- Build onboarding/setup checklist + shortcut coach + basic safe actions earlier.

### C. Power-User Productivity First
- Build live state + actions earlier, but keep minimal health gating and diagnostics in foundation.

---

## 5) Target Users

- Existing `yabai/skhd` users who want better visibility and safer controls.
- New users adopting tiling on macOS who prefer click-first onboarding.
- Power users who want quick macro actions without scripting everything.

---

## 6) Scope

## In Scope (v1)
- Menu bar app + TilePilot window.
- First-run setup/recovery checklist ("Doctor").
- Capability detection and compatibility summary (machine/OS/tooling).
- Live WM state (displays/spaces/windows).
- Action buttons for common operations.
- Shortcut reference parsed from `~/.config/skhd/skhdrc`.
- Health checks:
  - Accessibility permission status.
  - `yabai`/`skhd` daemon running state.
  - Mission Control settings required/recommended for reliable behavior.
  - Scripting-addition availability constraints (with reason categories).
  - macOS / `yabai` / `skhd` version visibility and warnings.
- Safe config editing for known sections and helper args.
- Event + command log (last N entries).
- Diagnostics export (sanitized, issue-report friendly).

## Out of Scope (v1)
- Full `.yabairc` and `skhdrc` semantic editor.
- Full visual tiling tree editor.
- Auto mode that continuously overrides user intent.
- In-app SIP modification or privileged installers.

---

## 7) User Experience & Information Architecture

## Menu Bar Quick Menu (always available)
- Minimal, high-frequency quick access only (top-level):
  - Open TilePilot
  - Open Window Behavior
  - Show Shortcuts
  - Focused window float/tile actions
  - Manual tiling / hover-focus recovery toggles
  - Align tiles (balance)
- Setup/diagnostics/admin actions are moved into a secondary submenu (not top-level clutter).
- The menu should be curated as a daily-use surface, not a dump of every feature.

## First-Run / Recovery Wizard (v1)
- Checklist-based onboarding flow.
- Detects missing permissions/settings and links to the right System Settings panes.
- Separates:
  - "Core features available now"
  - "Advanced features unavailable on this setup"
- Re-runnable anytime from menu bar and Health tab.

## TilePilot Window Tabs
1. **TilePilot** (main view)
   - Live map (Displays -> Desktops -> Windows).
   - Focused window controls.
   - Problem banners only when action is needed (not constant status chatter).
   - Future priority: search/find window + quick actions from list rows.
2. **Actions**
   - Large click-first action cards.
   - Capability-gated actions with explicit disabled reasons.
   - Needs finish cycle: better grouping/copy, macro explainers, and stronger quick-menu integration.
3. **Shortcuts**
   - Searchable, categorized shortcut reference from `skhdrc`.
   - Should also be a "learn the stack" surface, not only a raw parser output.
4. **Config**
   - Safe editor for essential bindings + helper script args.
   - Restore backup / restore last known good.
5. **Health**
   - Permissions, daemon state, Mission Control checks, scripting-addition status, degraded status.
   - Event/command log + recovery actions.
   - Diagnostics export.
6. **Setup**
   - First-run/fresh-machine install helper and setup checklist.

---

## 8) Functional Requirements

## 8.1 Doctor + Capability Detection (New v1.1 Priority)
- On launch and on-demand, detect:
  - macOS version/build (best effort).
  - CPU architecture.
  - `yabai` version (if installed).
  - `skhd` version (if installed).
  - Accessibility permission status.
  - `yabai` daemon running state.
  - `skhd` daemon running state.
  - Mission Control settings relevant to `yabai` reliability.
  - scripting-addition availability and failure category (when detectable).
- Capabilities must be represented as typed statuses, not a single boolean.
- The app must distinguish:
  - `available`
  - `degraded`
  - `blocked`
  - `unsupported`
  - `unknown`
- Each blocked/degraded capability should include:
  - short reason code
  - user-readable explanation
  - suggested recovery step(s)

## 8.2 Live State
- Query:
  - `yabai -m query --windows`
  - `yabai -m query --spaces`
  - `yabai -m query --displays`
- Fallback source (degraded context only):
  - `CGWindowListCopyWindowInfo` monitor-level totals.
- State must include source quality metadata:
  - `source`: `yabai | fallback | stale`
  - `lastUpdatedAt`
- Window identity must use window ID as primary key (not title).
- If capability checks indicate unsupported/blocked features, live state UI must reflect confidence limits.

## 8.3 Polling + Event Ingestion
- Periodic polling tiers:
  - Foreground/visible: 600-900 ms.
  - Background: 2-3 s.
- Event-triggered refresh with debounce/coalescing.
- Post-action immediate refresh.
- No blocking shell calls on main thread.
- Polling errors must be categorized (timeout, parse, command-not-found, permission, other).

## 8.4 Actions (v1 Catalog)
- Focus window direction.
- Move window direction.
- Focus space N.
- Send window to space N.
- `space --balance`
- `space --layout bsp` + `space --balance`
- `space --layout stack`
- `window --toggle float`
- One-shot "readable current space".
- One-shot browser relief (`max windows per lane` setting).
- Action labels and descriptions must use user-facing language first; engine commands/jargon are secondary.
- The `Actions` tab is a core product surface and must be treated as unfinished until:
  - action grouping is curated for daily use
  - action copy explains outcome (not command syntax)
  - advanced actions include contextual explainers/examples

## 8.5 Action Availability Contract
- Every action has:
  - `enabled` boolean.
  - `disabledReason` (required if disabled).
  - `requiredCapabilities` (machine-readable list).
- In degraded mode, workspace-precise actions are disabled with explicit reason text.
- If an action command exits successfully but observable state does not change, show "no visible effect" feedback and suggested checks.

## 8.5.1 Quick Access Curation (New v1.2)
- The menu bar right-click menu must remain intentionally minimal at top level.
- Top-level items should be limited to high-frequency actions users can reasonably perform many times per day.
- Setup, diagnostics, system settings, and daemon management actions should be grouped under a secondary submenu.
- Quick access entries should be reviewed/re-prioritized as major features are added (avoid legacy clutter drift).

## 8.5.2 Visual Feature Explainers (New v1.2)
- Add lightweight visual explainer modules/cards for advanced features, one concept at a time (examples):
  - Manual Tiling Mode
  - Hover Focus
  - App Rules (`Default` vs `Never Tile` vs `Always Tile`)
  - Browser Relief / layout macros
- Each explainer should include:
  - what problem it solves
  - before/after behavior (visual or diagrammatic)
  - one clear action button (enable/open/settings)
- Explain features in user language first; advanced jargon may appear in secondary detail text.

## 8.6 Shortcuts
- Parse `~/.config/skhd/skhdrc` line-by-line.
- Build `ShortcutEntry` list: combo, command, category, source line.
- Must tolerate malformed lines without crashing.
- Search + copy affordances.
- Flag entries that reference helper scripts/paths that no longer exist (best effort).

## 8.7 Config Editing (Safe Sections Only)
- Editable scope:
  - Known hotkeys block.
  - Known helper script args (`max windows per lane`).
- Unknown lines outside safe sections preserved byte-for-byte.
- Save pipeline:
  1. Create backup.
  2. Atomic write.
  3. Basic syntax sanity check.
  4. Restart affected service.
  5. Health verify.
  6. Auto-rollback on failure.
- One-click restore options available.
- Show diff preview before save (within editable scope only).

## 8.8 Health + Recovery
- Health state includes:
  - Accessibility status.
  - `yabai` running.
  - `skhd` running.
  - Mission Control checks.
  - scripting-addition status (typed, not boolean-only).
  - macOS / tool version summary and compatibility warnings.
  - degraded flag.
- Recovery actions:
  - Restart daemons.
  - Open relevant System Settings panes.
  - Refresh health checks.
  - Re-run Doctor checklist.
- Event/Command log shows last N:
  - command, duration, stdout/stderr snippets, status/error type.

## 8.9 Diagnostics Export (New v1.1)
- Export a sanitized diagnostics bundle/report containing:
  - SystemProfile (OS version, arch)
  - tool versions (if available)
  - capability matrix + statuses
  - health snapshot
  - recent command log metadata and short stderr excerpts
  - degraded-mode state and trigger reason
- Must avoid exporting full config contents by default.
- Provide "Copy issue-ready summary" text output for quick sharing.

---

## 9) Degraded Mode Requirements (Critical)

## Trigger
Enter degraded mode when `yabai` window total is materially below fallback count for `N` consecutive samples (anti-flap, recommended `N=3`).

## Recovery
Exit degraded mode after `M` consecutive healthy samples (recommended `M=5`).

## Behavior in Degraded Mode
- Show persistent degraded banner.
- Show monitor-level counts from fallback source.
- Do not claim reliable workspace mapping.
- Disable workspace-level misleading actions.
- Keep only actions with safe confidence.
- Show explicit guided recovery steps.
- Surface compatibility/update warnings if capability checks indicate likely OS-update or scripting-addition-related breakage.

---

## 10) Data Model (v1)

- `SystemProfile { macOSVersion, macOSBuild?, arch, yabaiVersion?, skhdVersion?, detectedAt }`
- `CapabilityState { key, status, reasonCode?, message, remediationSteps[] }`
- `DisplayState { id, name, focused, windowCount, source, lastUpdatedAt }`
- `SpaceState { index, label?, displayId, focused, visible, layout, windowCount, source, lastUpdatedAt }`
- `WindowState { id, app, space, display, floating, title, source, lastUpdatedAt }`
- `ShortcutEntry { combo, command, category, sourceLine }`
- `MissionControlCheck { key, expected, actual?, status, message }`
- `HealthState { accessibilityOK, yabaiRunning, skhdRunning, degraded, missionControlChecks[], capabilities[], compatibilityWarnings[] }`
- `ActionAvailability { actionId, enabled, disabledReason?, requiredCapabilities[] }`
- `EventLogEntry { timestamp, type, payloadSummary }`
- `CommandLogEntry { id, command, startedAt, endedAt?, durationMs?, exitStatus, stdout?, stderr?, errorType? }`
- `DiagnosticsReport { generatedAt, systemProfile, health, capabilities, recentCommands, degradedReason? }`

---

## 11) Non-Functional Requirements

- Menu opens quickly under load (target <150 ms).
- First useful state appears in the TilePilot window within 1 second.
- First Doctor result appears within 2 seconds on a healthy machine.
- All command execution off main thread.
- Robust timeout and cancellation handling.
- No crashes on malformed `skhdrc` lines or transient query failures.
- Clear uncertainty and stale-state labeling in UI.
- Diagnostics export completes without blocking UI interaction.

---

## 12) Success Metrics (v1)

- User can complete core workflow without memorizing shortcuts.
- 100% of unavailable actions show explicit disable reason.
- Config save failures are auto-rolled back and recoverable in one click.
- Degraded state is visible and does not expose misleading workspace controls.
- Reduced "what is happening?" complaints via event/command visibility.
- First-run users can identify blocked prerequisites from the in-app checklist without opening external docs.
- Diagnostics export produces issue-ready summaries that reduce back-and-forth for common setup failures.

---

## 13) Milestones and Timeline (Replanned v1.2 - Next Major Cycle)

### Baseline (Already Built / In App)
- Foundation shell, command runner, setup/health checks, diagnostics export.
- Live state polling + degraded mode fallback.
- Window Behavior (manual tiling / hover focus / app rules) + managed `yabairc` editing.
- Shortcuts and Config MVPs.
- Basic Actions UI and menu bar quick access.

### Next Major Cycle Goal
Finish TilePilot as a coherent daily-use product by improving:
- `Actions` completeness and learnability
- visual explainers for advanced features
- main-view find/control workflows
- quick access curation and contextual shortcuts

### Proposed next-cycle sequence (Estimate: 12-18 dev days)

1. **Actions Completion Pass (3-4d)**
   - Curate action groups for real user tasks (not command buckets only).
   - Rewrite action copy to describe outcomes in user language.
   - Add/finish high-value macros (browser relief, readable layouts, common recovery actions).
   - Improve per-action disabled reasons and "why nothing changed" feedback.

2. **Visual Explainers v1 (2-3d)**
   - Add explainer cards/modules for:
     - Manual Tiling Mode
     - Hover Focus
     - App Rules
     - 1-2 powerful layout macros
   - Include clear before/after explanation and one-click entry action.

3. **Main View (`TilePilot`) Workflow Upgrade (2-3d)**
   - Add search/filter for finding a window by app/title.
   - Add row actions (`Focus`, `Tile`, `Float`, `Toggle`) where appropriate.
   - Add optional "current desktop only" mode for lower noise.
   - Continue removing non-actionable status/debug clutter.

4. **Quick Access Menu Curation Pass (1-2d)**
   - Context-aware top-level quick items (focused window present vs not present).
   - Promote only frequent actions.
   - Keep setup/diagnostics hidden behind submenu and trim further if needed.

5. **Teachability + Copy Sweep (1-2d)**
   - Wording consistency across tabs (`desktops`, `float`, `auto-tile`, etc.).
   - Clarify advanced terms only where needed.
   - Ensure UI answers "Do I care?" and "What should I do next?"

6. **Reliability / UX Hardening Pass (2-4d)**
   - Event-driven refresh improvements (or quieter smarter polling).
   - Edge-case fixes for app-name matching and window visibility quirks.
   - Final regression pass on setup/bootstrap/window behavior persistence.

### Alternate priority adjustments
- **Adoption-first:** move Visual Explainers to milestone 1 (parallel with Actions completion).
- **Power-user-first:** move Main View Workflow Upgrade ahead of Visual Explainers, but keep copy cleanup in same cycle.

---

## 14) Testing Plan

## Unit
- `skhdrc` parser: valid/malformed lines.
- Config merge/write/rollback logic.
- Degraded detection and anti-flap transitions.
- Action availability derivation from capability matrix.
- Error categorization and reason-code mapping.

## Integration
- Command timeout/failure behavior.
- Daemon restart + health refresh.
- Atomic write failure and rollback path.
- Diagnostics export sanitization (no full config by default).
- Doctor rerun after settings changes.

## Manual
- Permission denied scenarios.
- Mission Control settings misconfiguration scenarios.
- Monitor add/remove and space transitions.
- Crowded desktop relief workflows.
- Degraded mode UX and recovery completion.
- macOS update / scripting-addition broken-state messaging (simulated if needed).

---

## 15) Release & Distribution (Direct Distribution)

- Signed Developer ID app.
- Notarized and stapled release artifact.
- Initial format: signed `.dmg`.
- Manual update checks for v1.
- Publish release notes + checksum.
- Clean-machine install verification before public release.
- Verify first-run checklist behavior on a clean machine.

---

## 16) Default Settings (v1)

- Manual-first mode: **ON**
- Auto-relief: **OFF** (one-shot only)
- Max windows per lane: **6**
- Essential shortcuts surfaced first: **8-10 actions**
- Diagnostics log retention: **Last 200 commands/events** (configurable later)

---

## 17) Risks and Mitigations

- **State inconsistency:** source labeling + anti-flap degraded detection.
- **Permission confusion:** explicit health checklist + one-click recovery.
- **Mission Control misconfiguration:** dedicated checks + plain-language explanations.
- **Scripting-addition / macOS update churn:** typed capability statuses + compatibility warnings + diagnostics export.
- **Config corruption risk:** transactional save + automatic rollback.
- **Event bursts/races:** debounced/coalesced refresh + periodic polling fallback.
- **False-positive capability detection:** conservative statusing (`unknown` over incorrect certainty) + log-backed diagnostics.

---

## 18) Future Considerations (Post-v1)

- Expanded rule management UI.
- Optional auto-update channel.
- More advanced macro editor.
- Enhanced visual layout inspector/tree view.
- Compatibility knowledge-base updates (local or remote metadata).
