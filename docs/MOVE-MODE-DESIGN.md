# Move Mode

Open **Move Mode** from the settings sidebar or with `/fqol move`. Select a target
from the toolbar or click a custom display. Disabled custom displays get sample
previews. The Paladin seal appears for Paladins.

Drag to move. **- / +** scales the selected target. Horizontal bars also have
corner grips for independent width and height adjustment. **Group** links health
and power within their display or attaches the Paladin seal to personal health.
Party members share one layout. The swing timer has its own layout.

The target list includes visible minimap, chat, action-bar, player-frame,
target-frame and quest-tracker frames. When a family has multiple visible
frames, **Group** applies a move or scale to the family together. Switch it off
to adjust a frame separately. These frames show a movable outline during editing.
**Reset** clears the selected frames' offsets and scale overrides.

Nearby edges and centres snap to other custom displays and the screen. Gold
guides show the active alignment. Hold **Shift** to bypass snapping.

**Done & Settings** saves and reopens the same page and tab. **Cancel** or Escape
discards the session and returns to settings. Entering combat discards pending
edits and queues the return to settings. Logging out or reloading discards
pending edits.

`MoveMode.lua` owns selection, snap geometry, and the toolbar. `Resources.lua`
owns the custom-display editing session. `Elements.lua` stores per-frame Blizzard
offsets and scale overrides and applies them out of combat.
