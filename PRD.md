# TilePilot (GUI for yabai/skhd) - Product Requirements Document (v1.1)

## Document Control
- Version: 1.1
- Date: 2026-02-25
- Status: Draft (implementation-ready, priorities-aware)
- Platform: macOS (direct distribution, non-App-Store)

---

## 1) Product Summary

TilePilot is a native macOS menu bar app that adds a click-first control layer on top of `yabai` and `skhd`.
It improves observability, reliability, and ease of use without replacing the underlying window manager engine.

### North Star
- Keep `yabai/skhd` as the engine.
- Enable click-first operation and gradual shortcut learning.
- Never fake state when `yabai` is degraded, incompatible, or uncertain.

### Strategy Note (v1.1)
- Prioritize support-load reduction and recovery clarity before deeper GUI controls.
- Treat capability detection ("what can work on this machine right now") as a first-class feature.

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

## Menu Bar Status Menu (always available)
- Current focused space/layout (or explicit "unknown/degraded" status).
- WM health badge + capability badge.
- Quick actions:
  - Balance
  - Stack
  - BSP + Balance
  - Toggle Float
  - Browser Relief
- Entry point: **Open TilePilot Window**.
- Entry point: **Run Doctor / Recovery Check**.

## First-Run / Recovery Wizard (v1)
- Checklist-based onboarding flow.
- Detects missing permissions/settings and links to the right System Settings panes.
- Separates:
  - "Core features available now"
  - "Advanced features unavailable on this setup"
- Re-runnable anytime from menu bar and Health tab.

## TilePilot Window Tabs
1. **TilePilot** (main view)
   - Live map (Displays -> Spaces -> Windows).
   - Recommended next actions.
   - Source quality and stale-state labels.
2. **Actions**
   - Large click-first action cards.
   - Macro buttons (e.g., send+follow, float+center).
   - Per-action capability requirements + disabled reasons.
3. **Shortcuts**
   - Searchable, categorized shortcut reference from `skhdrc`.
4. **Config**
   - Safe editor for essential bindings + helper script args.
   - Restore backup / restore last known good.
5. **Health**
   - Permissions, daemon state, Mission Control checks, scripting-addition status, degraded status.
   - Event/command log + recovery actions.
   - Diagnostics export.

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

## 8.5 Action Availability Contract
- Every action has:
  - `enabled` boolean.
  - `disabledReason` (required if disabled).
  - `requiredCapabilities` (machine-readable list).
- In degraded mode, workspace-precise actions are disabled with explicit reason text.
- If an action command exits successfully but observable state does not change, show "no visible effect" feedback and suggested checks.

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

## 13) Milestones and Timeline (Estimate: 15-19 dev days)

### Default order below assumes Priority Profile A (Support-Load Reduction First).

1. **Foundation + Doctor Shell (3d)**
   - App shell, menu bar, command runner, async execution model.
   - SystemProfile detection + capability model types.
   - Health badge plumbing.
2. **Setup/Recovery Wizard + Health Checks (2-3d)**
   - First-run checklist (permissions, Mission Control, daemon state).
   - Re-runnable Doctor flow.
   - Recovery action hooks + deep links.
3. **Live State + Degraded Detection (2d)**
   - Typed models, polling tiers, degraded detection, source labels.
4. **Diagnostics + Reliability Hardening (2d)**
   - Command/error categorization.
   - Diagnostics export + issue-ready summary.
   - Timeouts, retries, stale-state handling.
5. **Actions UI (2d)**
   - Action cards, availability gating, result feedback/toasts.
   - Post-action verification messaging.
6. **Shortcuts (2d)**
   - Parse/categorize/search `skhdrc`.
7. **Config MVP (2-3d)**
   - Safe-section editor + diff preview + backup/restore/rollback.
8. **Polish + Onboarding Copy (1-2d)**
   - In-app docs, wording polish, empty/error states.

### Alternate ordering notes
- **Priority B (New-User Adoption):** move Shortcuts to milestone 4, keep Doctor/Health before Actions.
- **Priority C (Power-User Productivity):** move Actions UI to milestone 4, but do not skip capability gating.

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
