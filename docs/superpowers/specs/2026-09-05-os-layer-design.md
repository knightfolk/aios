# OS Layer — Desktop Switching, Menu/Status Bar, Drag-Drop, Context Menus, Resizing

Date: 2026-09-05
Status: Approved by standing directive ("plan and implement")

## Goal

Make the shell behave like a real macOS app: per-project desktops that
restore their full working state on switch, a native menu bar + status item,
drag-and-drop card arrangement, right-click context menus, and proper
resizing behavior — all wired to the same journaling engine, no invented
state.

## Work items

1. **Per-project desktop session state** — `DesktopSessionStore` persists,
   per project: card order/pinning (extends `ProjectLayout`), selected
   expert, expanded panels, scrub position. Switching desktops swaps the
   whole working state atomically; tested round-trip + isolation.
2. **Command layer + native menu bar** — `AppCommand` enum +
   `CommandRouter` (pure, tested: every command maps to a journaling engine
   call or UI state change). The native macOS menu bar (SwiftUI
   `.commands`): App/Edit standard menus, File (New Note / New Inbox
   Capture), View (Full Screen, Toggle Ruler, Refresh), Desktop (Switch to
   1–9, Next/Previous), Control (Emergency Stop). An `NSStatusItem` shows
   live activity/needs-you counts from projections with an Emergency Stop
   trigger — deterministic, no models.
3. **Drag & drop + right-click** — cards reorder via SwiftUI
   draggable/dropDestination; order persists into the per-project layout
   (pure ordering model, tested: pinned-first, stable, reorder function).
   Context menus on cards expose their real actions (Needs You → resolve,
   Note → promote, Checkpoint → branch/restore, Expert → consult, any card
   → copy summary).
4. **Resizing & window behavior** — window frame autosave, min sizes per
   surface, card scale cycling from context menu (persisted), grid stays
   adaptive at every size.

## Non-goals

Detachable windows/panels (needs AppKit window plumbing pass), Spaces-style
animations, menu-bar extra popovers beyond status counts.

## Testing

Stores/view models: round-trips, isolation, ordering math, command routing
(journaled effects). AppKit pieces (menus, status item) verified by build +
launch smoke; commands they emit route through the same tested router.
