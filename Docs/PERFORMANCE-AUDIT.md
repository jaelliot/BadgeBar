# Performance investigation (2026-10-13)

## Scope and baseline status

This is a source review and measurement plan, not a claim of measured speedups. No macOS Instruments trace, CPU profile, battery profile, or successful macOS CI run was available to this review. Do not treat this draft as performance-validated until the measurements below are collected.

## Hot-path map

1. BadgeMonitor.scheduleTimer creates a repeating timer (default: 1 second). If no apps are selected, the timer is suspended.
2. BadgeMonitor.tick performs an Accessibility trust check, calls BadgeReader.badges, compares badge states, and calls the status-bar synchronization callback.
3. BadgeReader.badges requests AXStatusLabel synchronously from the Dock for each cached tile; it performs a bounded Dock traversal when handles are missing or stale.
4. StatusItemController.sync loops through selected apps, but it updates native status-button text/tint only when the displayed state changes. Each app's template icon is drawn/cached once, not regenerated for every badge count.
5. SettingsView's app picker displays Spotlight-discovered applications. Sorting is now done once at discovery completion, with only filtering on search.

## Low-risk changes in this PR

- Allow a 10% Timer.tolerance so macOS can coalesce wakeups; do not change the user's selected 1/2/5-second cadence.
- Eliminate the duplicate status-bar sync triggered by a monitored-app change (the monitor already invokes the callback).
- Sort installed applications once after Spotlight discovery, preserving the existing case-insensitive order.
- Add static-name os signpost intervals for PollCycle, AXBadgeRead, AXDockWalk, and StatusBarSync. Signposts contain **no app names, badge values, message contents, user IDs, or other application data**.

## Follow-up: lightweight monochrome status UI

The proposed follow-up replaces per-notification composited color NSImages with
AppKit's template icons and NSStatusBarButton titles. It also shares one
event-driven RunningApps cache between badge polling and status-bar visibility,
eliminating repeated running-process queries while a monitored app lacks a
Dock tile.

This is a code-level optimization; **no runtime savings have been measured**.
Compare allocations, memory residency, CPU wakeups, AX reads, and status-bar
update latency before and after the change. Verify icon legibility in dark and
light menu bars, including Slack's neutral hash symbol. Badge text should
never become an unbounded layout string: numeric values cap at 99+; arbitrary
AX labels render a neutral dot. Floating alerts use translucent material
and monochrome outlines instead of red fills.

The Dock AX reads still execute on MainActor. These changes do **not**
address that largest potential UI-stall source; moving AX calls to a worker
remains a separate experiment requiring macOS profiling and concurrency tests.

## Instrumentation protocol

Use Xcode Instruments on a real macOS host. Attach to a locally compiled and signed BadgeBar.app and record the Points of Interest, Time Profiler, and System Trace / Energy diagnostics. Signpost names:

| Signpost | Location | What it measures |
| --- | --- | --- |
| PollCycle | BadgeMonitor.tick | Total synchronous poll processing time on main actor |
| AXBadgeRead | BadgeReader.badges | Dock badge sampling including full walks |
| AXDockWalk | BadgeReader.walkDock | Slow-path tree traversal |
| StatusBarSync | StatusItemController.sync | Menu-bar synchronization/render decisions |

Capture the same scenario before and after optimization (preferably on one Mac with identical foreground workload, power state and Dock configuration). Report p50/p95/p99 wall times, total wakeups, process CPU percentage, energy impact, memory delta, Dock walk count, and delay between a change to a Dock badge and its menu-bar update. Record the sampling window; do not extrapolate from a few seconds.

Test matrix:

- 0 monitored apps: verify zero recurring polling and no unnecessary process wakeups.
- 1, 3, and 10 monitored apps with stable badges for at least 10 minutes each.
- Poll intervals of 1, 2, and 5 seconds; measure CPU, wakeups and notification lag.
- A Slack badge appearing/increasing/disappearing; repeat during full-screen use.
- Dock process restart, app launch/quit, missing Dock tile, and Accessibility revocation/regrant.
- Rapid changes to the watched-app list, toggle count/dot display, and search the installed-app picker.
- Verify rendered icons, floating alerts, login persistence and keyboard responsiveness.
- Verify high-contrast white-on-dark and black-on-light display; no branded colors in menu-bar icons or unread indicators.
- Verify badge labels: nil, 1, 9+, 99+, 100, huge numeric input, and nonnumeric AX text (render as neutral dot).
- Compare process-state lookups during prolonged missing Dock tile with one and ten monitored apps.

## Follow-up experiments (not yet implemented)

### P0: isolate synchronous AX IPC from the UI thread

All badge sampling currently happens on @MainActor. The cache makes normal polls cheap, but a hung Dock or repeated AX errors can still stall user interaction. Prototype a serialized worker/actor with clearly owned AX handles, one outstanding poll at a time, cancellation, generation IDs to reject stale responses, and main-actor delivery. Avoid unbounded concurrent Accessibility calls and validate that AX objects are safely used under Swift concurrency rules. Compare latency and CPU under normal and failure conditions. Do not blindly move AXUIElement references across actors.

### P1: per-element timeouts and error-aware backoff

AXUIElementSetMessagingTimeout on the Dock application element does not automatically apply to previously cached tile elements. Investigate applying a measured timeout to individual tile handles and differentiating transient cannotComplete from genuinely invalid UI elements. Exponential backoff after repeated Dock timeouts can reduce main-thread stalls, but should reset promptly when the Dock restarts or permission returns. Existing 512-node traversal cap trades completeness for bounded work: test large/atypical Docks.

### P1: event-driven assistance / adaptive scheduling

Test whether AXObserver delivers reliable value-change notifications for Dock tiles across supported macOS versions. Do not replace polling until notifications are empirically verified; registration failure must fall back to polling. Alternatively, reduce polling when all selected GUI apps are not running and immediately resume on launch. Note that NSWorkspace launch events do not cover all background/LSUIElement applications, so include a periodic recovery check.

### P2: update-only rendering

StatusItemController.sync executes each tick to reflect global Settings defaults and running-app state, but image drawing is already guarded by lastRenderKey. Refactor only after implementing explicit settings-change and workspace-state events so turning on hide/show is immediate. Avoid optimizing small collection passes before AX IPC has been profiled.

## Acceptance criteria

1. Run swift build -c release and swift test on a supported macOS build host, plus shell build-script checks.
2. Verify all manual behavior scenarios from the matrix.
3. Confirm fewer wakeups or less wall time with Instruments versus baseline; publish hardware/macOS version, configuration and measurements.
4. No regressions in notification delivery at the documented poll interval, and no new sensitive permissions, telemetry, or network calls.
5. Keep performance experiments on reviewed branches. Do not ship a new DMG based on this work without independent release signing/notarization and provenance review.

## Platform references

- Apple Timer.tolerance guidance: https://developer.apple.com/documentation/foundation/timer
- Apple macOS energy efficiency and timers: https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html
- Apple AXUIElementSetMessagingTimeout: https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout
- Apple OSSignposter and Instruments: https://developer.apple.com/documentation/os/ossignposter
