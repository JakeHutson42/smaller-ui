# Resource previews and seal reminder

Implemented in **1.5.0-local11**. Local testing build; not published.

Compatibility: query event metadata before any optional combat-log registration.
Callback-only, invalid, restricted or uninspectable events are never probed by
calling RegisterEvent inside pcall: that attempt can itself trigger WoW's blocked
action dialog. On unsupported clients, separate HoT/DoT estimates are unavailable
and their controls are disabled. Native incoming healing and live HP are independent.
Own blocked/forbidden actions are recorded for support, with Blizzard's notice intact.

- Live health/power: native `Immediate` updates on unit events, before decorative
  and prediction work. Numeric HP uses the same API sample as its fill. No polling
  interval, easing or forecast amount controls current HP. Optional smoothing
  applies only to a dim historical trail. Damage/heal tint stays inside the
  current filled region. Actual health events interrupt demos.
- Equal-width linked bars share left/right anchors. Different dimensions and
  independent positions remain supported. Both fills use identical border insets.
- Colours: health defaults to red; power uses the active resource's colour.
  Each display has native health/power pickers, an automatic-power checkbox and
  a colour-only reset. Preview/cancel works without rewriting HP, moving bars
  or restarting their values. Saved colours are finite RGB values between 0 and 1,
  stored per character. Incoming healing uses lighter shades of health's colour.
- Text and styling: separate health/power formats, font, automatic/manual size,
  alignment, text colour, short numbers and background opacity. Bar borders can
  be hidden or coloured separately. Advanced text/resource panels start collapsed.
  Native percentage curves handle restricted numbers; Lua never divides secret
  health/power values. Compact numbers are optional and use public values only.
- Resource overrides: one colour per power token, per display/character. Druid
  form changes choose the matching override. Generic fixed power colours remain
  available. Cancelling a new override restores the absence of that override.
- Move mode: named selection, eight-screen-pixel snapping with guides, Shift
  bypass, independent saved offsets, whole-session Cancel/Escape and combat
  rollback. Applies to custom bars and the Paladin seal. No permanent snap links.

- Incoming heals: a lighter extension starts at current health. Prefer
  WoW's native prediction calculator to handle overhealing, heal absorbs and
  restricted values. Fall back to the incoming-heals API with native clipping.
  The server supplies the estimate; no spell coefficients or tooltip parsing.
- HoTs: a translucent pale extension follows incoming healing. After two observed
  ticks on the same unit, spell and caster, estimate ticks due in the next
  five seconds, bounded by the active aura's expiration. Smooth recent tick
  amounts with a simple rolling average. Samples last for this session only.
- DoTs: optional muted red overlays the rightmost part of current health.
  Uses the same five-second observation method. Disabled by default.
- Paladin seals: recognize known seal spell IDs and localized spell names for
  other ranks. Show the active icon; retain the last spell ID per character
  for a grey icon and `!` when missing. Unreadable status shows `?`. Anchor
  beside personal health, with independent drag, size and offsets.
- Dimensions: arrows save one field immediately. Widths, heights and offsets
  step by one; scale by 0.01. Holding repeats after 350 ms, then every 70 ms.
  Typed values still use Apply. Bounds remain enforced.

`Forecasts.lua` owns prediction rendering and temporary tick samples. `Seal.lua`
owns the class indicator. `Resources.lua` supplies frame layout, saved defaults
and editing. `ResourceStyle.lua` handles text/style validation and native formatting;
`ResourceStyleOptions.lua` builds expandable style controls. `Options.lua` supplies
reusable controls; `ResourceOptions.lua` contains the settings. No external libraries
are required.
`MoveMode.lua` supplies shared movement/snapping and editor-only overlays.

Periodic estimates require readable combat-log ticks, caster identity and aura
expiry. They deliberately disappear when data is missing or restricted. They
are not exact future totals: critical strikes, refreshes, dispels, haste,
mitigation and healing modifiers can change the outcome. There is no estimate
before the second observed tick of an application. Native incoming healing
remains usable independently. Instant heals may land before a cast preview
can appear.

## Local verification

Automated Lua 5.1 checks cover incoming values, cancellation, overheal, heal
absorbs, secret values, periodic learning/removal, pet/party forecasts, seal
ranks/localization/reminders, icon positioning and arrow hold/release/bounds.
Documentation previews are labelled illustrations, not game screenshots.

Live-health checks include 600 rapid in-combat changes without a timer/frame
advance, zero/one HP, resurrection, maximum-health changes, native restricted
values, display-before-prediction ordering, and interrupted demos. Geometry
checks resolve equal inner/outer edges at scales 0.5, 0.67, 0.8, 1 and 1.25.
These checks exercise mocked APIs; actual client rendering still needs testing.

In WoW Forever, test a self-heal cast and cancellation; apply a HoT/DoT long
enough to observe two ticks; remove/refresh it; test personal, pet and party
bars. On a Paladin, activate and consume/expire a seal, move its icon, reload,
and confirm the grey reminder. Hold/release arrows and close settings while
holding. Verify restricted/PvP contexts do not produce errors or stale estimates.
