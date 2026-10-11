# ThreatMeterNP

A lightweight World of Warcraft nameplate add-on that shows two extra pieces of information on
enemy nameplates:

- **Target of target** — who the unit is currently targeting.
- **Threat gap** — how far ahead you are of the next-highest threat holder while tanking, or
  how far behind the top threat holder while not.

ThreatMeterNP doesn't replace or reskin your nameplates — it attaches directly to whatever
nameplate frame is already on screen, so it works alongside **Blizzard default nameplates,
Plater, and ElvUI** without needing a different version for each.

## Status

v1 and v2 validated in-game, including exact threat percentages and the player threat list
(v0.9.1; renamed from ThreatWatch at this version — settings carry over automatically via a
one-time migration, see [requirements.md](requirements.md)). See
[requirements.md](requirements.md) for the full spec and [infos.md](infos.md) for the WoW API
research behind the implementation.

## Features

| Label | Shows | Visible on |
|---|---|---|
| Target of target | Name of whoever the nameplate's unit is targeting | Enemy nameplates only |
| Threat | Your own threat on the unit, in a configurable format — Numeric, Percentage, or both — falling back to a fixed **Low**/**Medium**/**High** indicator (green→yellow→red, same scale for tanks and DPS) only on the rare unit where no exact value is available at all | Enemy nameplates only |

- Per-label position (X/Y), text alignment (Left/Middle/Right — which edge of the text sits at the offset), font (from [LibSharedMedia](https://www.curseforge.com/wow/addons/libsharedmedia-3-0)), font size, and color — target-of-target has one color (or "color by class" — colors the name by the targeted player's class, falling back to the plain color for NPCs), threat has separate colors for "tanking" vs "not tanking".
- **Threat display format**: Numeric, Percentage, or Numeric - Percentage — applies everywhere threat is shown.
- **Display threat owner**: prefixes the single threat display with who currently has aggro (`Bob: 87%`, or `You: 87%`) — works unconditionally since it reuses the target-of-target lookup rather than threat-table ranking.
- **Player list mode**: instead of just your own threat, show 1-3 (slider) group/raid members ranked by threat status, each with name (optionally class-colored) and value. Degrades gracefully to fewer rows if fewer members have any registered threat — see "How it works."
  - **When showing 1 player**: choose "My Threat" (always you — the default) or "Top Threat" (whoever currently ranks #1, which might not be you).
  - **Lower row size**: shrink rows below #1 to a percentage (50-100%) of the normal font size.
- **Background**: an optional solid-color backdrop (with adjustable alpha) behind the threat display, sized to fit whatever's actually shown — the single value or the whole player list.
- Visibility toggles: enabled while solo / in a group / in a raid, independently.
- **Debug Mode**: shows made-up names and threat numbers on every nameplate (friendly or hostile, solo or grouped) so you can check how your current settings look without a real pull. Turn it off before actually playing — see "How it works."
- Minimap button (click to open options) and `/threatmeternp` or `/tmnp` slash command.
- All settings persist account-wide via SavedVariables.

## Compatibility

- **Nameplate add-ons**: Blizzard default, [Plater](https://www.curseforge.com/wow/addons/plater-nameplates), ElvUI.
- **Client**: built and tested against WoW Forever Beta (client-reported TOC interface `16001`).
  Not yet verified on retail or other Classic clients — the `.toc` currently declares only
  `16001`; add the relevant `## Interface:` values yourself if you try it elsewhere, and please
  report back what works.
- **Dependencies**: none required to install. Ace3 (`AceAddon`, `AceConfig`/`AceConfigDialog`,
  `AceDB`, `AceConsole`, `AceGUI`), `LibSharedMedia-3.0`, and `LibDataBroker-1.1`/`LibDBIcon-1.0`
  are bundled inside `ThreatMeterNP/libs/` — not a separate addon you need to install.

## Installation

### Manual

1. Download or clone this repository.
2. Copy the `ThreatMeterNP` folder into your WoW client's `Interface\AddOns\` directory, so the
   result is `...\Interface\AddOns\ThreatMeterNP\ThreatMeterNP.toc`.
3. Enable **ThreatMeterNP** in the in-game AddOns list.

### From source, with the deploy script

`Deploy-ThreatMeterNP.bat` copies `ThreatMeterNP/` straight into a configured client's AddOns
folder (defaults to the WoW Forever Beta install used during development). Edit the
`WOW_ADDONS_DIR` line at the top of the script to point at your own client, then run it after
every change.

### CurseForge

Not published yet. Planned for once v1 is stable — a proper `.pkgmeta`/CurseForge project
setup is tracked as future work, not part of this initial version.

## Packaging a release zip

`Package-ThreatMeterNP.bat` zips up `ThreatMeterNP/` only (no `requirements.md`, `infos.md`,
`README.md`, or the `.bat` scripts) into `dist\ThreatMeterNP-<version>.zip`, with the addon
folder at the zip root — ready to attach to a GitHub release or upload to CurseForge as-is.
The version in the filename is read straight from `## Version:` in `ThreatMeterNP.toc`, so bump
that before packaging a new release.

## Configuration

Open the options panel via the minimap button, `/threatmeternp`, `/tmnp`, or the Blizzard
AddOns options list. Settings save automatically (`ThreatMeterNPDB`, account-wide — one profile
shared across all characters, not per-character). Changes apply live to nameplates already on
screen, no `/reload` needed.

## How it works

ThreatMeterNP anchors its labels to the plate frame returned by
`C_NamePlate.GetNamePlateForUnit(unitToken)` — the same generic attach point WeakAuras uses for
its own nameplate-anchored visuals — rather than reaching into a specific nameplate add-on's
internal frame layout. That keeps it addon-agnostic, at the cost of not being pixel-perfect
flush with every skin's health bar (see [requirements.md §2](requirements.md) for the reasoning).

Threat values on this client come back as Blizzard "secret" values — addon code can't read,
compare, or `string.format()` them directly (see [infos.md](infos.md)). Two techniques work
around that, both discovered by reading how other local add-ons (EllesmereUI, Blizzard's own
default UI) handle the same restriction:

- **Single display**: a secret value can still be handed straight to a widget's own
  `:SetFormattedText`, which renders it without ever exposing the value back to Lua — that's
  how the exact Numeric/Percentage display works. If no value is available at all for a unit
  (not just secret — genuinely absent), it falls back to a fixed **Low / Medium / High**
  indicator (green→yellow→red) built from `UnitThreatSituation`, the one threat signal that's
  reliably non-secret.
- **Player list**: ranking multiple units requires *comparing* their threat, and raw threat
  values turned out to be secret for every group member on this client (never usable for
  sorting) — so the list ranks by `UnitThreatSituation`'s status instead, the same reliably
  non-secret signal the single display's fallback uses. Each row's actual displayed value still
  goes through the widget-sink technique independently, so it can show a real number even
  though it couldn't be used to determine row order. Shows fewer rows than configured (or falls
  back to the single display) only when fewer members have any registered threat at all.

**Debug Mode** is a deliberately separate code path rather than fake data threaded through the
above — since made-up numbers are never secret, none of the secret-value handling applies, and
keeping it separate means it can't accidentally affect the real, already-working display logic.
It reuses the same row-rendering code the real list uses, so it looks pixel-identical to
reality for whatever settings you have configured, just with a small fixed pool of fake
names/classes whose threat values re-roll every update tick.

## Known limitations

- No per-nameplate-skin alignment tuning — one offset applies across Blizzard/Plater/ElvUI
  alike (see [requirements.md §2](requirements.md)).
- Player list mode falls back to showing just your own value (never blank) if literally nobody
  has any registered threat on the unit — otherwise it now ranks and shows real rows (see "How
  it works"), but this hasn't been confirmed yet against a live multi-member pull.

## License

[MIT](LICENSE) — covers `Options.lua` and `ThreatMeterNP.lua`. The bundled libraries in
`ThreatMeterNP/libs/` keep their own existing licenses.

## Credits

- Threat-gap and target-of-target logic adapted from a WeakAuras custom trigger/text function
  (see [requirements.md §10](requirements.md) for the original snippets).
- Bundles the Ace3 library suite, LibSharedMedia-3.0, LibDataBroker-1.1, and LibDBIcon-1.0 —
  standard, widely-embedded open WoW addon libraries.
