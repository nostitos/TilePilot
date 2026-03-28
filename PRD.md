# TilePilot - Product Requirements Document (v1.3)

## Document Control
- Version: 1.3
- Date: 2026-03-27
- Status: Active development (bundled-helper baseline shipped)
- Platform: macOS (direct distribution, non-App-Store)

---

## 1) Product Summary

TilePilot is a native macOS menu bar app that makes `yabai` + `skhd` practical for daily use through:
- live visibility into desktops and windows
- click-first actions
- safe config management
- guided setup and recovery

### North Star
- Keep `yabai` and `skhd` as the runtime engine.
- Make the product usable without terminal-first habits.
- Prefer truthful degraded states over optimistic but wrong UI.
- Use user language first: desktops, windows, floating, tiled, right-click menu.

### Locked Product Decisions
- End users should not need Homebrew or Xcode Command Line Tools.
- TilePilot ships bundled `yabai` and `skhd` helpers and installs/manages them per-user.
- Guided Setup is the primary onboarding and recovery flow.
- Unsupported scripting-addition / SIP-dependent features are not part of the supported product path.
- MegaMap screenshots are memory-only. They are not persisted to disk.
- `Actions` and `Shortcuts` are one combined product surface.

---

## 2) Current Product State

## 2.1 Shipped Baseline
- Native menu bar app shell with left-click main window and right-click action menu.
- Main tabs:
  - `Overview`
  - `Behaviors`
  - `Actions & Shortcuts`
  - `Appearance`
  - `Config Files`
  - `System`
- Bundled helper install and management:
  - install bundled helpers into the user account
  - manage per-user LaunchAgents
  - start/restart helper services in-app
- Guided Setup:
  - auto-opens when essential setup is incomplete
  - manual reopen from `System` and the menu bar
  - covers helper install, helper services, Accessibility, Start at Login, Mission Control review, and optional Screen Recording for MegaMap
- Live state:
  - displays, desktops, windows
  - degraded-mode handling when `yabai` is unavailable or unreliable
  - desktop overlays and mini-map views
- MegaMap:
  - screenshot-based desktop view
  - RAM-only capture cache
  - optional Screen Recording for real screenshots
  - synthetic fallback when Screen Recording is unavailable
- Window behavior controls:
  - desktop tiling on/off
  - app defaults
  - app rules
  - hover focus
  - cursor follows focus
  - yabai mouse dragging/drop settings
  - global tiling spacing controls
- Unified actions and shortcuts:
  - feature-backed actions
  - imported `skhdrc` entries
  - pinning to the right-click menu
  - shortcut recording and editing
- Appearance controls:
  - badges
  - outline overlay
  - outline width
  - global tiling spacing controls
- Config management:
  - managed `yabairc` / `skhdrc` sections
  - backups and restore flows
  - raw file editing in `Config Files`
- Signed/notarized DMG release flow.

## 2.2 Important Recent Behavior Decisions
- Main layout actions now use outcome-based naming:
  - `Float All Windows on This Desktop`
  - `Tile All Windows on This Desktop`
  - `Arrange Windows into a Floating Grid`
  - `Retile Windows into a Balanced Tiled Layout`
  - `Rebalance Tiled Window Sizes`
- Legacy `Auto Layout` naming is no longer a primary concept.
  - old aliases map to the floating-grid action
- Legacy `bootstrap.sh` is treated as a reset/helper script, not a normal first-class layout action
- Map cleanup hides limited/minimized/helper/backdrop junk when enabled
- MegaMap should reuse last in-memory captures within the current app session only

## 2.3 Known Product Gaps
- Overview still needs stronger find-and-act workflows for large desktop/window sets
- MegaMap capture timing and desktop association need more hardening under fast desktop switching
- The combined `Actions & Shortcuts` surface is much better, but still needs curation and simplification
- Some helper or transient windows still require ongoing heuristics to avoid visual junk in maps/overlays
- Learning/discoverability is still mostly copy-driven; visual explainers are still missing

---

## 3) Product Requirements (Current)

## 3.1 Setup and Recovery
- TilePilot must install and manage bundled helper binaries without requiring Homebrew, Terminal, or Command Line Tools on end-user machines.
- Guided Setup must be the primary path whenever essential requirements are missing.
- Essential setup blockers:
  - helpers not installed
  - helper services not running
- Recommended but non-blocking setup items:
  - Accessibility review
  - Start at Login
  - Mission Control review
- Optional feature-specific setup:
  - Screen Recording for MegaMap screenshots
- Returning from external settings or permission prompts must trigger automatic recheck.

## 3.2 Live State and Degraded Truthfulness
- TilePilot must prefer correct live state over stale or optimistic assumptions.
- If `yabai` is unavailable or unreliable, the UI must say so directly and route users to Guided Setup or recovery actions.
- Windows shown in maps/overlays should exclude obvious junk surfaces when the cleanup setting is enabled:
  - minimized windows
  - app-hidden windows
  - stale/helper windows
  - backdrop/dialog surfaces
  - transient child dialogs when a larger real sibling exists

## 3.3 Main Window / Overview
- `Overview` is the primary daily-use surface.
- It should support:
  - seeing displays and desktops in a way that matches physical layout vertically
  - understanding which desktops and windows are active
  - jumping quickly to desktops/windows
  - obvious recovery when helpers or permissions are missing
- Degraded Overview states must always show a visible recovery path, not subtle or low-contrast links.

## 3.4 MegaMap
- MegaMap is a manual, higher-resolution desktop overview.
- Real screenshots require Screen Recording.
- Without Screen Recording, MegaMap must show a clear synthetic fallback.
- Screenshots must remain in RAM only and never be persisted to disk.
- MegaMap should reuse already captured screenshots within the current app session.
- Each desktop tile should show capture age in relative form.
- Refresh actions must be explicit:
  - refresh one desktop
  - refresh all desktops

## 3.5 Actions and Shortcuts
- `Actions & Shortcuts` is the single product surface for:
  - first-class feature actions
  - imported shortcuts
  - right-click menu pinning
- User-facing action naming must describe outcomes, especially final floating vs tiled state.
- The right-click menu should be curated around frequent actions and clearly represented in-app.
- Legacy shortcut/script entries should resolve to current user-facing names where TilePilot can confidently map them.
- Unknown custom commands may remain visible, but should not degrade the clarity of first-class actions.

## 3.6 Behaviors and Appearance
- `Behaviors` owns behavior semantics:
  - desktop tiling
  - app rules/defaults
  - focus/cursor behavior
  - yabai mouse drag/drop behavior
- `Appearance` owns visual and layout presentation controls:
  - badges
  - outline overlay
  - outline width
  - screen edge padding
  - gap between tiled windows
- UI wording in both tabs should stay short, concrete, and outcome-focused.

## 3.7 Config Safety
- TilePilot-managed config edits must preserve user content outside managed sections.
- Backups and restore must remain available through the product UI.
- First-save behavior must backfill existing unmanaged config when adopting new controlled settings such as spacing or yabai mouse controls.

---

## 4) Decisions That Made Older PRD Items Irrelevant

The following older assumptions are no longer current product direction:

- **Homebrew / Terminal installer as the primary setup path**
  - replaced by bundled helper installation
- **Separate `Actions` tab**
  - replaced by combined `Actions & Shortcuts`
- **SIP / scripting-addition repair as a supported setup goal**
  - removed from supported product path
- **Persistent MegaMap screenshot cache on disk**
  - explicitly rejected for privacy reasons
- **`Auto Layout` as a primary product action name**
  - retired in favor of direct floating-grid naming
- **`Bootstrap` as a normal layout action**
  - now treated as legacy reset plumbing only

These should not drive new roadmap work unless product direction changes again.

---

## 5) Suggested Next Steps

## 5.1 Priority 1 - Overview Workflow Upgrade
- Add strong search/filter in `Overview` for app/title/window ID
- Add row-level quick actions where useful:
  - focus
  - jump to desktop
  - float
  - tile
  - bring to front
- Add a lower-noise “current desktop only” or similar focused mode

Why:
- This is the biggest remaining daily-use gap
- The core data and actions already exist
- It improves discoverability without expanding setup complexity

## 5.2 Priority 2 - Actions & Shortcuts Curation
- Tighten grouping and reduce wording drift
- Distinguish clearly between:
  - first-class TilePilot actions
  - imported custom shortcuts
  - legacy aliases
- Add better descriptions/examples for high-value layout actions and mouse controls
- Keep right-click menu editing obvious and bounded

Why:
- The surface now works, but still feels heavier than it should
- This is the most visible “product polish” gap after setup

## 5.3 Priority 3 - MegaMap Reliability Hardening
- Continue improving desktop-switch capture timing
- Add better internal diagnostics for capture-to-desktop mismatches
- Keep fallback behavior explicit when a desktop could not be refreshed
- Preserve privacy constraint: no disk caching

Why:
- MegaMap is valuable, but users notice correctness bugs immediately

## 5.4 Priority 4 - Visual Explainers for Advanced Concepts
- Add compact explainers for:
  - desktop auto-tiling
  - app rules
  - hover focus
  - right-click menu pinning
  - floating vs tiled outcomes for layout actions

Why:
- The product still depends too much on text for teaching
- These explainers should clarify concepts without reintroducing jargon

## 5.5 Priority 5 - Ongoing Window/Junk Heuristic Hardening
- Keep tightening overlay/map exclusion heuristics for:
  - transient dialogs
  - backdrop surfaces
  - app helper windows
  - weird window-manager mismatches

Why:
- This is a recurring correctness issue in real usage
- It should remain narrow, generic, and non-app-specific where possible

---

## 6) Non-Goals (Still Intentionally Out of Scope)

- Full semantic editor for arbitrary `yabairc` / `skhdrc`
- Continuous automation that overrides user intent
- Full graphical tiling-tree editor
- In-app SIP modification or Recovery Mode workflows
- Shipping advanced scripting-addition-dependent desktop/window features as part of the core supported product
- Persisting MegaMap screenshots to disk

---

## 7) Success Criteria for the Next Cycle

- New or migrated users can recover from missing helpers/permissions using Guided Setup without terminal knowledge
- Users can find and act on a specific window quickly from `Overview`
- Main layout actions are understandable without prior `yabai` vocabulary
- The right-click menu feels intentionally curated, not accidental
- MegaMap remains privacy-safe while becoming more reliable within a session
- The product stops accumulating legacy naming that conflicts with current behavior
