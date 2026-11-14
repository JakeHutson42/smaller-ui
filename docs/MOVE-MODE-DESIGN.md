# Move mode

Implemented in **1.5.0-local8** for local testing. Nothing published.

Use **Move mode** on the personal, party or pet settings page. A temporary named
outline shows the selected display/bar. Drag bars or the Paladin seal icon;
corner grips still resize bars. Existing linked/independent sizing remains.

Nearby edges and centres snap within eight screen pixels. Gold guides show active
alignment with other custom bars, screen edges and screen centre. **Hold Shift**
to bypass snapping immediately. Raw pointer movement is kept independent of the
snap offset, so releasing Shift cannot accumulate drift.

**Done** saves. **Cancel/Escape** restores the whole session, including positions
and sizes. Entering combat also cancels and restores the saved layout. Guides and
selection outlines disappear outside editing. A lost mouse-release callback is
recovered from the button state. Logging out or reloading cancels unconfirmed
changes instead of persisting an unfinished edit.

`MoveMode.lua` handles canvas coordinates, device-pixel thresholds, raw cursor
movement, bounds, guide rendering and selection. `Resources.lua` saves group or
bar offsets; `Seal.lua` saves the seal's health-relative offset. Snap targets
exclude elements that move with the selection, including coupled party clones
and seals attached to moving personal health. Positions are stored independently;
snapping never creates permanent parent/child links to another display.

Automated geometry checks cover release-time Shift, fractional scales, screen
centre/bounds, party members, seal offsets, persistence, rollback and combat.
Actual pointer feel and client rendering still need in-game testing.

Future discussion: keyboard pixel nudges, persistent grouping, and moving default
WoW elements with separate handling for layout ownership and combat protection.
