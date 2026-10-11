# Requirements — ThreatMeterNP

Working repo folder stays `platertank`. The addon's name has changed twice: it was built as a
generic nameplate tool (pivoting from an earlier Plater-specific idea, see §2), shipped and
developed through v0.9.0 as **ThreatWatch**, then renamed to **ThreatMeterNP** (folder
`Interface/AddOns/ThreatMeterNP`, `ThreatMeterNP.toc`) as of v0.9.1 — see "v0.9.1: renamed from
ThreatWatch" in §13 for the full rename (folders, Lua globals, slash commands, SavedVariables
key + migration, deploy/package scripts, docs). Everything in this file below this point uses
the current name throughout, including in sections describing work done before the rename, to
keep the document internally consistent — the `ThreatWatch` name only still appears literally
where it's specifically about the rename itself (§13) or the SavedVariables migration code.

**Status**: **v1.0 released** (`.toc` `## Version: 1.0`, flagged as the first stable release
per the user's request after v0.9.8's background-width fix). All v1 (§1-§12) and v2 (§13)
feature work shipped and validated in-game — options panel, minimap button, slash command,
SavedVariables persistence, and class coloring all confirmed working. Icon replaced by the
user (2026-09-20) and license chosen (MIT, copyright "Tag" — see [LICENSE](LICENSE)).
Remaining open items (multi-client TOC, CurseForge packaging) are post-1.0 polish, not
functional gaps.

## Current state (read this first — orientation after context loss)

Everything below this section is the decision-by-decision history of how ThreatMeterNP got here
(kept for "why" questions). This section is a current-as-of-last-edit snapshot so work can
resume without reading all of it.

**Version**: 1.0 (first stable release). Both v1 and v2 feature sets shipped and validated in-game by the user,
including exact threat percentages and the player threat list. Renamed from ThreatWatch to
ThreatMeterNP at v0.9.1 (see §13). Both `enabled` toggles (§13 v0.9.4/v0.9.5) check
`~= false` rather than truthiness, specifically so they default to "on" for existing profiles
that predate the setting, since AceDB doesn't retroactively backfill a brand-new nested key
into an already-populated sub-table. Single-display threat text now explicitly calls `:Show()`
on success (§13 v0.9.6) — a regression from the v0.8.0 background refactor meant it never
became visible when list mode was off. Player list rows now color the name by the threat
(tanking/not-tanking) color whenever "Color name by class" is off, instead of plain white
(§13 v0.9.7). The player-list background now spans the widest rendered row rather than just
the first/last row's width, fixing overlap with "Lower row size" set below 100% (§13 v0.9.8).

**What ThreatMeterNP does today**, on every enemy/hostile nameplate:
- **Target of target**: shows who the nameplate's unit is currently targeting (`T: Name`),
  optionally colored by that target's class (checkbox, players only — falls back to a plain
  configured color for NPCs or when the checkbox is off). A separate **"Show Target of
  target"** toggle (`targetOfTarget.enabled`, default on) turns the whole label off entirely.
- **Text alignment** (both labels, `align`: Left/Middle/Right, default Middle): which edge of
  the text sits at the configured X/Y offset — doubles as the anchor point (`SetPoint`) and the
  multi-line justification (`SetJustifyH`, relevant for the threat player list's rows), since
  "LEFT"/"CENTER"/"RIGHT" are valid values for both.
- **Threat**, with its own **"Show Threat"** toggle (`threat.enabled`, default on) that turns
  the whole label off entirely — same on/off pattern as target-of-target's, added right after
  it on request. One of two modes (toggle in options, `listMode`) when enabled:
  - **Single** (default): the player's own threat on that unit, in a configurable format —
    Numeric, Percentage, or Numeric - Percentage (`displayFormat` dropdown). Renders real exact
    values via a widget-sink technique (see "Key techniques" below), confirmed working in-game
    — not an estimate. Falls back to a fixed Low/Medium/High indicator only on the rare unit
    where no value is available at all. Optional **"Display threat owner"** toggle
    (`showOwner`, single mode only) prefixes the value with the name of whoever currently has
    aggro (`"Bob: 87%"`, or `"You: 87%"`) — reuses the target-of-target lookup (mob's current
    target = aggro holder), not threat-table ranking, so it works unconditionally.
  - **List**: instead of just the player, shows 1-3 (`listCount`, slider) group/raid members,
    each with name (optionally class-colored — `listColorByClass`) and value in the same
    display-format setting. **Ranked by `UnitThreatSituation` status (0-3), not raw threat
    magnitude** — v0.6.x ranked by raw threat and it never actually populated beyond one row on
    this client (raw threat was secret for every member, every time); v0.7.0 switched the
    ranking key to `status`, the same signal the single-display fallback already depends on
    reliably. Falls back to the single-value display only when literally nobody has any
    registered threat on the unit. See "v0.7.0" in §13 for the full rationale.
    - **When `listCount == 1`**: `soloListMode` ("My Threat" default, or "Top Threat") decides
      whether that one row is forced to be the player ("My Threat" — bypasses ranking entirely
      and just runs the single display) or whoever ranks #1 ("Top Threat" — might not be you).
    - **When `listCount > 1`**: `secondaryScale` (50-100%, default 100 = no change) shrinks
      rows below #1 relative to the configured font size. Implemented as a stack of independent
      FontString widgets (`widgets.listRows[]`), one per row — not one multi-line block of text
      like before — because WoW text can't mix font sizes within a single FontString.
  - **Background** (`bgEnabled` + `bgColor` with alpha): a solid-color backdrop behind whichever
    of the two display modes is active, sized to the actual rendered text's bounds (single
    widget or the full row stack) plus a small padding, so it's not a separate per-mode setting.
- Visibility: independently toggleable for solo / in a group / in a raid (`visibility.solo`/
  `.party`/`.raid`).
- **Debug Mode** (`debugMode`, top-level toggle, its own "Debug" section in options): shows
  made-up names/classes/threat numbers on *every* nameplate — friendly or hostile, solo or
  grouped, bypassing both the enemy-only filter and the visibility toggles above — so the
  current settings' appearance can be checked without a real pull. A small fixed roster of 8
  fake name/class pairs is generated once per session; each member's threat values re-roll
  every update tick. Implemented as a fully separate rendering path
  (`RenderDebugPreview`/`RollDebugRoster` in ThreatMeterNP.lua) that reuses the same
  position/font/color helpers (including `RenderListRow`, shared with the real list) rather
  than threading fake data through the real threat-reading functions — so it's pixel-identical
  to reality for the same settings, with zero risk to the already-working real-data code paths.
- Options panel (sliders for X/Y offset, font dropdown sourced from LibSharedMedia, font size,
  color pickers, every toggle above) reachable via minimap icon click, `/threatmeternp`, `/tmnp`,
  or the Blizzard AddOns list. All settings persist account-wide (one shared profile, not
  per-character) via SavedVariables (`ThreatMeterNPDB`).

**File layout** (repo root `C:\Repo\wow\lua\platertank`):
- `ThreatMeterNP/` — the addon: `ThreatMeterNP.toc`, `ThreatMeterNP.lua` (nameplate engine — threat
  calc, target-of-target, widget lifecycle, event/polling driver), `Options.lua` (Ace3 addon
  object, defaults table, options table, minimap button, slash command), `libs/` (vendored
  Ace3 + LibSharedMedia-3.0 + LibDataBroker-1.1 + LibDBIcon-1.0), `media/icon.tga` (the user's
  own icon, replacing an earlier placeholder).
- `Deploy-ThreatMeterNP.bat` — copies `ThreatMeterNP/` into the WoW Forever Beta client's AddOns
  folder; target path is a variable (`WOW_ADDONS_DIR`) at the top of the script.
- `Package-ThreatMeterNP.bat` — zips `ThreatMeterNP/` into `dist\ThreatMeterNP-<version>.zip` for
  release (addon folder only, no dev files); version read straight from the `.toc`.
- `LICENSE` — MIT, copyright "Tag".
- `README.md` — GitHub-facing project description, kept in sync with this file.
- `infos.md` — WoW API research log (client identity, the secret-value system in full depth,
  vendored library sources, API gotchas discovered along the way). Read it for technical
  "why/how" detail beyond what's summarized here.

**Key techniques** (full technical depth in infos.md):
- This client wraps sensitive values (most threat data) in Blizzard "secret values": addon Lua
  can hold/pass them around but not compare, do arithmetic, or `string.format()` them — any of
  those throw. Detect with the global `issecretvalue(v)` — **not** `type(v)`, which still
  reports the real underlying type ("number"/"boolean") for a secret value.
- A secret value can still be **displayed**: handing it straight to a widget's own
  `:SetFormattedText`/`:SetText` is a sanctioned sink that renders it without ever exposing the
  value back to Lua. This is how the single-display exact Numeric/Percentage mode works
  (`ApplyExactThreatPercentage` in ThreatMeterNP.lua) — discovered by reading EllesmereUI's own
  nameplate threat-percent code, a real working addon on this exact client.
- **Ranking/comparing** multiple secret-prone values (the player list) IS possible — contrary
  to an earlier wrong conclusion in this file — but only among whichever units' values happen
  to be non-secret at that moment. Pattern: read each candidate, guard with `issecretvalue()`,
  silently skip any that's secret, `table.sort` the rest with an ordinary comparison
  (`CollectThreatEntries`/`ApplyThreatList` in ThreatMeterNP.lua). Modeled directly on
  EllesmereUI's own threat-list collector.
- Generic nameplate anchoring: attaches to `C_NamePlate.GetNamePlateForUnit(unitToken)` directly
  — not a specific skin's internal frame — so it works across Blizzard default/Plater/ElvUI
  without per-addon code paths.

**Open items** (polish, not functional gaps):
- CurseForge packaging (`.pkgmeta`, multi-flavor TOC setup) not started.
- `.toc` `## Interface:` only declares `16001` (this client's custom version) — untested on
  retail or other Classic flavors.
- Player list mode not yet confirmed against a live group with multiple real members.

## 1. Concept

In WoW Forever, add information to existing nameplates (Blizzard default, Plater, or ElvUI):

- For each nameplate, show the name of the unit's current target ("target of target").
- For each nameplate, show the threat the player currently has on that unit (as a number for now).

## 2. Type of project

**Decision: standalone WoW addon** (own `.toc`, own folder in `Interface/AddOns`), not a
Plater mod/script.

**Decision: generic across nameplate addons**, not Plater-specific. It must work on top of
Blizzard default nameplates, Plater, and ElvUI alike.

- Anchor to the plate frame returned by `C_NamePlate.GetNamePlateForUnit(unitToken)` directly,
  not to skin-specific internals like Plater's `unitFrame.healthBar`. This is the same
  approach WeakAuras uses to attach visuals to nameplates, and it's addon-agnostic by
  construction.
- Trade-off accepted: alignment will be "close enough" across skins rather than pixel-perfect
  flush with each skin's health bar, since Plater/ElvUI/Blizzard each size and position their
  health bar differently inside the plate frame. Per-skin fine-tuning is out of scope for v1
  (see §8).
- Resize/reposition handling must hook the plate frame's own `OnSizeChanged`/`OnUpdate`
  rather than addon-specific hooks like `Plater.UpdatePlateSize`, to stay addon-agnostic.

## 3. Target game version

- WoW Forever, currently WoW Forever Beta (client slot `_classic_beta_`, self-reports TOC
  interface `16001` — see [infos.md](infos.md) for how that was derived).

## 4. Core functionality

- A new nameplate appearing triggers a new display for that unit.
- Displays a string on the nameplate: name of the current target of the unit that nameplate
  belongs to (target of target).
- Displays a number on the nameplate: threat gap between the player and the next competitor
  on that unit's threat table, matching the logic in the WeakAura reference code (§10):
  - While tanking: player's threat minus the #2 threat holder's (how much buffer before
    losing aggro).
  - While not tanking: player's threat minus the #1 threat holder's (how far behind before
    pulling aggro).
  - Requires iterating group members' `UnitDetailedThreatSituation` each update, not a single
    API call — see [infos.md](infos.md) for the confirmed function signature.
- Only shown on **enemy/hostile nameplates**. Friendly and neutral nameplates get neither
  label.

## 5. Nameplate compatibility

- Must work with Blizzard default nameplates, Plater, and ElvUI without addon-specific code
  paths for each (see decision in §2).
- Not required to match each skin's exact health-bar position/size — a generic offset from the
  plate frame is acceptable for v1.

## 6. Configuration & data

For v1, for each label (target-of-target, threat):

- X and Y position, offset from the center of the nameplate.
- Font displayed.
- Size of font.
- Visibility setting (always on, in group only, for tank role only, etc.).

## 7. UI/visual output

For v1:

- Just a label for Threat and a label for Target of Target, for each nameplate. No bars,
  icons, or coloring beyond plain text.

## 8. Scope for v1

In scope:

- Target of target.
- Threat (numeric).

Out of scope:

- Options UI, visual customization beyond the config in §6.
- Per-skin pixel-perfect alignment (see §2 trade-off).

## 9. Local references to use

- `D:\World of Warcraft\` — multiple WoW client installs live here.
- `C:\Repo\wow\lua\API\Wow Forever\` — the Lua API reference dump for this project.
- See [infos.md](infos.md) for what's already been scanned from these (client identity, Plater
  and PlaterTOT structure, confirmed API signatures) so it doesn't need re-scanning.

## 10. Existing code references

### Target of target (WeakAura custom text function)

```lua
function()
    if  UnitExists(aura_env.region.cloneId.."-target") then
        if aura_env.config.opt  == 2 then
            if UnitName(aura_env.region.cloneId.."-target") ~= UnitName("player") then
                return WA_ClassColorName(aura_env.region.cloneId.."-target")
            else return ""
            end
        elseif aura_env.config.opt == 3  then
            if UnitName(aura_env.region.cloneId.."-target") == UnitName("player") then
                return WA_ClassColorName(aura_env.region.cloneId.."-target")
            else return ""
            end
        elseif aura_env.config.opt == 1 then
            return WA_ClassColorName(aura_env.region.cloneId.."-target")
        end
    else return ""
    end
end
```

### Threat values (WeakAura custom state trigger)

Triggers: `NAME_PLATE_UNIT_ADDED`, `NAME_PLATE_UNIT_REMOVED`, `UNIT_THREAT_LIST_UPDATE`,
`GROUP_ROSTER_UPDATE`

Variables:

```lua
{
    status = {
        display = "Threat Status",
        type = "select",
        values = {
            [1] = "Untanked",
            [2] = "Insecurely Tanking",
            [3] = "Tanking",
            [4] = "Tanked by Other Tank",
            [5] = "Securely tanking"
        }
    }
}
```

Code:

```lua
function(allstates, event, unitId)
    if not unitId then
        return
    end

    if event == "NAME_PLATE_UNIT_REMOVED" then
        local state = allstates[unitId]
        if state then
            state.show = false
            state.changed = true
            return true
        end

    elseif unitId ~= "target" then
        if UnitIsPlayer(unitId) then
            return
        end

        local isTanking, threatStatus, _, _, threatValue = UnitDetailedThreatSituation("player", unitId)

        if not threatValue then
            return
        end

        local firstUnit, firstThreat, secondUnit, secondThreat = aura_env.ThreatFunc(unitId)
        local displayValue

        if isTanking then
            displayValue = threatValue - secondThreat
            if Round(math.abs(displayValue) / 100) > aura_env.secureThreatValue then
                -- Player is securely tanking the unit
                threatStatus = 5
            elseif firstUnit and secondUnit and not UnitIsUnit(secondUnit, "player") and (UnitGroupRolesAssigned(secondUnit) == 'TANK') then
                -- Player is tanking the unit, another tank is second on threat
                threatStatus = 3
            else
                -- Player is tanking the unit, non tank is close on threat
                threatStatus = 2
            end
        else
            displayValue = threatValue - firstThreat
            if firstUnit and not UnitIsUnit(firstUnit, "player") and (GetPartyAssignment("MAINTANK",firstUnit) or (UnitGroupRolesAssigned(firstUnit) == 'TANK')) then
                -- Player is not tanking the unit, another tank is first on threat
                threatStatus = 4
            end
        end

        allstates[unitId] = allstates[unitId] or {unit = unitId}
        local state = allstates[unitId]
        state.changed = true
        state.show = true
        state.status = threatStatus < 1 and 1 or threatStatus
        state.value = Round(math.abs(displayValue) / 100)
        return true
    end
end

aura_env.secureThreatValue = aura_env.config.secureThreatValue

aura_env.ThreatFunc = function(unit)
    local firstUnit, secondUnit
    local firstThreat, secondThreat = 0, 0
    local threat, pet
    for member in WA_IterateGroupMembers() do
        threat = select(5, UnitDetailedThreatSituation(member, unit))
        if threat then
            if threat > firstThreat then
                secondUnit = firstUnit
                secondThreat = firstThreat
                firstUnit = member
                firstThreat = threat
            elseif threat > secondThreat then
                secondUnit = member
                secondThreat = threat
            end
        end

        pet = member.."pet"
        if UnitExists(pet) then
            threat = select(5, UnitDetailedThreatSituation(pet, unit))
            if threat then
                if threat > firstThreat then
                    secondUnit = firstUnit
                    secondThreat = firstThreat
                    firstUnit = pet
                    firstThreat = threat
                elseif threat > secondThreat then
                    secondUnit = pet
                    secondThreat = threat
                end
            end
        end
    end
    return firstUnit, firstThreat, secondUnit, secondThreat
end
```

## 11. Deployment

- The addon must be usable as-is: proper `.toc`, correct folder name, loadable in-game.
- Build a `.bat` script to deploy it easily into the WoW Forever Beta AddOns folder for now.
  Will need to support deploying to other client folders in the future — keep the target path
  easy to change (e.g. a variable at the top of the script) rather than hardcoding it deep
  inside.

## 12. Remaining assumptions (not yet confirmed)

Small implementation defaults not explicitly specified — flagging so they're visible rather
than silently guessed. Correct any of these if wrong:

- **Update throttling**: threat-table events (`UNIT_THREAT_LIST_UPDATE` etc.) can fire very
  frequently in combat. Assuming a small throttle (e.g. recompute at most every ~0.2s per
  unit) rather than recalculating on every single event, for performance.
- **Restricted/"secret" threat values**: confirmed in testing (not just theoretical) —
  `UnitDetailedThreatSituation`'s raw threat values come back as Blizzard "secret values" on
  this client even solo, outside any instance (see infos.md for the full writeup and the
  `issecretvalue()` detection gotcha). **Superseded twice since this was written** — see the
  "v0.4.0" and "Correction" entries later in §13/infos.md: exact values ARE displayable (via a
  widget-sink technique) and ARE comparable/rankable among whichever units happen to be
  non-secret at a given moment (via the `issecretvalue()`-guard-and-skip pattern). The
  Low/Medium/High fallback described originally here is still real, just now a last resort
  rather than the common case.
- **Solo / no-group play**: the gap-to-competitor calc (§4) needs at least one other threat
  entry to compare against. Assuming that outside a group, with no second threat holder, the
  label either shows blank or just the player's raw threat vs. the unit's top holder (which
  may be the player itself) — needs a concrete fallback rule once implemented, but treating it
  as a low-priority edge case for v1 since this is a tank tool typically used in groups.
- **Label text format**: no exact string format specified. Assuming plain text, e.g. `T: Grommash`
  for target-of-target and a bare signed number (e.g. `+1240` / `-830`) for the threat gap — no
  icons, colors, or extra decoration for v1, per the "just a label" scope in §7.
- **Target-of-target self-reference**: if a unit is targeting the player, assuming the label
  still shows the player's own name (no special-casing to hide/highlight "targeting me"),
  since nothing in scope calls for that distinction.

## 13. v2 scope — options UI, minimap button, persistence

### Toolkit decision

**Vendored Ace3 + companion libraries**, bundled inside `ThreatMeterNP/libs/` (not a separate
required addon — stays consistent with the "no dependency" decision in §2):
`LibStub`, `CallbackHandler-1.0`, `AceAddon-3.0`, `AceConsole-3.0` (slash command), `AceDB-3.0`
(SavedVariables), `AceConfig-3.0` (includes `AceConfigRegistry-3.0`/`AceConfigCmd-3.0`/
`AceConfigDialog-3.0` — the options panel), `AceGUI-3.0` (widgets AceConfigDialog renders with),
`LibSharedMedia-3.0` (font dropdown), `LibDataBroker-1.1` + `LibDBIcon-1.0` (minimap button).

Vendored from `Plater/libs/` in the local WoW Forever Beta client rather than fetched fresh —
that exact copy is already proven to load correctly on this client's custom interface version
(16001), sidestepping any version-mismatch risk. Trade-off accepted: ~10 bundled library
folders added to the repo/zip; alternative was hand-rolling options UI, minimap button, and
SavedVariables from raw Blizzard APIs (rejected — significantly more custom code for a very
well-trodden feature set).

### Options panel contents

For each of the two labels (target-of-target, threat):
- Slider: X offset.
- Slider: Y offset.
- Dropdown: font, sourced from `LibSharedMedia-3.0`'s registered font list.
- Slider: font size.
- Color picker: text color. For the threat label specifically, **separate color pickers per
  threat-color choice** (i.e. the existing `colorTanking` / `colorNotTanking` pair from v1 both
  become user-configurable, not just the one base text color).

Visibility checkboxes (independent, not mutually exclusive — see open question below):
- Enable while solo.
- Enable while in a group (party).
- Enable while in a raid.

### Minimap button + slash command

- Minimap icon (via `LibDBIcon-1.0` + a `LibDataBroker-1.1` data object) that opens the options
  panel on click.
- Icon art: initially a placeholder TGA borrowed from another installed addon
  (`BugSack/Media/icon.tga`); replaced by the user with their own icon on 2026-09-20.
- Slash command (`/threatwatch` or `/tw` at the time — renamed to `/threatmeternp`/`/tmnp` in
  v0.9.1 along with everything else, see that entry below) that also opens the options panel.

### Persistence

- All of the above (offsets, font, font size, colors, visibility checkboxes) saved via
  `AceDB-3.0`, declared in the `.toc` as `## SavedVariables: ThreatMeterNPDB`.
- Confirmed: single account-wide profile (`AceDB-3.0:New(..., true)`), not per-character.

### Target-of-target class coloring

- Checkbox: "Color by class" on the target-of-target label. When checked, the name is colored
  using the *targeted unit's* class color (e.g. if the enemy's target is a warrior, the label
  uses warrior brown) instead of the plain configured color. Players only — falls back to the
  configured color for NPC targets, since NPCs have no class color.
- When unchecked (default), behaves as before: the single configured color applies.
- The plain color picker is visually disabled (greyed out) while "Color by class" is checked,
  since it has no effect in that state.

### Threat fallback display: words over a fixed gradient

**Superseded as the primary display** by the EllesmereUI-derived exact-percentage technique
further down this section — at the time this was written, the manual raw-gap approach never
rendered on this client, so this tier was what actually showed up in practice. It's since been
demoted to a last-resort fallback for the rare unit with no threat value available at all; kept
here for the historical reasoning behind its word/color choices, which are unchanged.

Went through two fallback designs:
1. First pass: `UnitThreatLeadSituation`-based, 5 words (No Aggro / Safe / Low / Medium / High),
   asymmetric between tanking and not-tanking.
2. **Simplified per follow-up request** to exactly **3 words — Low / Medium / High — the same
   scale for tanks and DPS alike**, over a fixed green→yellow→red gradient (high = red, low =
   green). Describes threat *magnitude* you're holding, not a role-specific danger judgment —
   a tank reads "High" while tanking regardless of lead margin, since holding the top threat on
   a unit *is* high threat by definition. Driven by a single signal,
   `UnitThreatSituation`'s 0-3 status (0/1 = not tanking, increasingly close to pulling;
   2/3 = tanking, insecurely/securely), bucketed 0→Low, 1→Medium, 2-3→High.
   `UnitThreatLeadSituation` is no longer used at all — simpler code, one API call instead of
   two.

The user-configurable `colorTanking`/`colorNotTanking` pickers from earlier in this section
still exist and still apply to the raw-gap path — kept for forward compatibility in case a
different client or a future patch exposes real values — but in practice, on this client, the
fixed-gradient words are what's shown. The options panel says so in each color picker's
tooltip.

### Second attempt at exact numbers: Blizzard's own `threatShowNumeric` technique

Per follow-up request, investigated how Blizzard's own default unit frames show a real threat
percentage (the `threatShowNumeric` cvar) and ElvUI's threat meter, looking for a working
technique to reuse. Full writeup in [infos.md](infos.md). Summary:

- **ElvUI's threat meter** turned out to be the same single `UnitThreatSituation` call our
  fallback already uses (via its bundled oUF library) — confirms the fallback approach, not a
  new capability.
- **`threatShowNumeric`** led somewhere new: Blizzard's own numeric display reads
  `rawPercentage` (not `rawThreat`) while not tanking, and a separate dedicated function,
  `UnitThreatPercentageOfLead`, while tanking — a single two-unit query, no group iteration.
  Neither of these specific values had actually been tested for secrecy before (the original
  raw-gap attempt only ever touched `rawThreat` via manual group iteration).
- Implemented as a tier and deployed, but this specific attempt (`rawPercentage` /
  `UnitThreatPercentageOfLead`, read and formatted via Lua's own `string.format`) was superseded
  before being confirmed working or failing — see below.

### Third attempt: the actual breakthrough, via EllesmereUI (not ElvUI)

User correction: meant **EllesmereUI**, a large modular UI suite actually installed on the
project's real target client (`_classic_beta_`) and purpose-built for its secret-value system —
not ElvUI, which isn't installed there. Full technical writeup in [infos.md](infos.md).
EllesmereUI's own nameplate threat-percent feature (`NP_UpdateThreatPct` /
`EllesmereUI.PaintThreatPct`) revealed the actual unlock: a secret number **can** be displayed
to the player, just not read by addon Lua — the restriction is specifically on Lua-side
comparison/arithmetic/`string.format`, not on handing the value to a widget's own
`:SetFormattedText`/`:SetText` method, which is a sanctioned "sink" that formats and renders
server/C-side without ever exposing the value back to the addon's Lua code.

**Rewritten accordingly** (`ApplyExactThreatPercentage` in ThreatMeterNP.lua, replacing the
`string.format`-based attempt): calls `UnitDetailedThreatSituation`, hands `scaledPercentage`
(3rd return) straight to `text:SetFormattedText("%.0f%%", pct)` without ever reading it in Lua.
For color: uses `GetThreatStatusColor` (a Blizzard global) when `status` isn't secret, and
`C_CurveUtil.EvaluateColorValueFromBoolean` — a Blizzard "secret-safe select" that branches
between two known plain colors using a possibly-secret `isTanking` boolean without Lua ever
reading it — when it is. Deployed; **genuinely likely to work this time**, since it's modeled
directly on a real, proven-working local addon on this exact client, not inferred from
documentation. Still needs the user's in-game confirmation.

**Confirmed working** by the user after deploying — real `NN%` values now render on nameplates.

### v0.4.0: display format option + player threat list

**Display format** (`profile.threat.displayFormat`, select: Numeric / Percentage / Numeric -
Percentage): applies to both the single "my threat" display and the new list below. Default
kept at Percentage (2) to match already-confirmed-working behavior.

**Player list** (`profile.threat.listMode`, toggle — replaces the single display when on):
originally told the user true ranking wasn't achievable; **that was wrong**, corrected after
the user pushed back with "how does EllesmereUI do a threat list then?" — see
[infos.md](infos.md) "Correction: secret-value comparison IS possible" for the full story.
Short version: ranking multiple units by threat requires comparing values that *might* be
secret, but a value that *isn't* secret compares completely normally; the fix is to read each
candidate, skip any that comes back secret (`issecretvalue()`-guarded), and sort/rank only
what's left — exactly the pattern EllesmereUI's own threat-list collector uses
(`EllesmereUIForeverEssentials_ThreatData.lua`). Implemented as
`CollectThreatEntries`/`ApplyThreatList` in ThreatMeterNP.lua.

- Row count: configurable 1, 2, or 3 (`listCount`) — started as "2 or 3" per the original
  request, widened to include 1 on a follow-up request.
- Each row: name (optionally class-colored via a new `listColorByClass` toggle, separate from
  target-of-target's own color-by-class option) + threat value in the chosen display format,
  colored by that row's own tanking status (reusing `colorTanking`/`colorNotTanking`).
- Gracefully shows fewer than the configured count (or nothing at all) when fewer group
  members' values happen to be readable at that moment — expected behavior under the
  constraint above, not a bug, matching EllesmereUI's own degradation.
- Deployed; not yet confirmed in a live group test.

### v0.4.1: list row count widened to 1-3

`listCount` dropdown values changed from `{2, 3}` to `{1, 2, 3}` on request — no other logic
change needed (`ApplyThreatList` already used `math.min(listCount, #entries)`, which handles 1
correctly on its own).

### v0.5.0: text alignment (Left/Middle/Right)

New `align` setting per label (`targetOfTarget.align`, `threat.align`; default `"CENTER"`,
matching prior behavior exactly, so existing saved profiles are unaffected). One string does
double duty in `ApplyLabelSettings` (ThreatMeterNP.lua):

```lua
local align = settings.align or "CENTER"
text:SetJustifyH(align)
text:SetPoint(align, plate, "CENTER", settings.offsetX, settings.offsetY)
```

`"LEFT"`/`"CENTER"`/`"RIGHT"` are valid values for both a FontString's `SetJustifyH` (multi-line
text justification — matters for the threat player list's rows, which can have differently
sized lines) and `SetPoint`'s anchor point (which edge of the text sits at the X/Y offset — the
actual "align to the offset" behavior requested: Left anchors the text's left edge at the
offset and it grows rightward, Right the mirror, Middle/Center is the original centered
behavior). No separate lookup table needed since the point names and justify values are
identical strings.

### v0.6.0: "Display threat owner" option

New `showOwner` toggle (single-display mode only — the options entry hides itself while list
mode is on, since the list already shows names). When enabled, prefixes the threat value with
the name of whoever currently holds top threat: `"Bob: 87%"`, or `"You: 87%"` when that's the
player.

Key realization: the unit holding top threat on a mob is, by definition, whoever that mob is
actively attacking — so this needed **no new threat-ranking logic at all**, just the same
mob-target lookup (`unitToken.."target"`) the target-of-target label already uses
(`GetThreatOwnerPrefix` in ThreatMeterNP.lua). It works unconditionally, independent of whether
exact threat values happen to be secret, because it never touches the threat table — plain
identity data, not threat data. The prefix is woven into the same `SetFormattedText` calls
`ApplyExactThreatPercentage`/`ApplyThreatLevelFallback` already make (mixing a plain `%s`
prefix with a secret numeric `%.0f` in one sink call is fine — the sink doesn't care which of
its arguments are secret).

### v0.6.1: fix — list mode showed nothing at all, including the player's own value

Reported by the user: enabling "Show a player list instead" made the threat label go
completely blank, even for the player's own threat, which displays fine outside list mode.

Root cause: `ApplyThreatList` only shows anything if `CollectThreatEntries` finds at least one
group member whose **raw** threat value is non-secret (needed to sort/rank by at all — see the
"Correction" entry above on why ranking needs genuinely-readable values, unlike single display
which can show a secret value via the widget-sink trick without ever reading it). On this
client, raw threat is apparently secret essentially always, including for the player's own
query — the same thing confirmed back when the manual raw-gap approach was first built. So
`entries` comes back empty, `ApplyThreatList` returned `false`, and — unlike single mode, which
always has the Low/Medium/High fallback underneath it — list mode had no fallback at all below
an empty ranking, so the whole label went blank.

**Fix**: when ranking finds zero entries, `ApplyThreatList` now falls back to the same
single-value display (`ApplyExactThreatPercentage`, then `ApplyThreatLevelFallback`) used
outside list mode, so at minimum the player's own value still shows.

**Open question this raises**: does the ranked list ever actually populate with more than one
row on this client, in any content? Unknown — the EllesmereUI code this was modeled on assumes
it sometimes does ("Forever hands the threat API over readable"), but that hasn't been observed
here. If the user tries list mode in an actual multi-member group and it's still only ever
showing the single-value fallback (never real rows), that's evidence true ranking may be
effectively dead on this client regardless of group size, and the feature should be
reconsidered (e.g. built around `UnitThreatSituation`'s coarse status instead, which IS
reliably readable, trading exact ranking for a reliable "who's tanking vs not" list).

### v0.6.2: options panel layout — less cramped

User feedback: the options page looked messy, no line break after each element. Cause: AceGUI
packs sibling elements side by side within a row unless each one explicitly claims the full row
width — none of ThreatMeterNP's options set `width`, so sliders/dropdowns/color pickers/toggles
were flowing together based on available space instead of one-per-line. Fix: added
`width = "full"` to every real option in `LabelOptions` (both labels) — the visibility group's
three toggles (Solo/Group/Raid) were deliberately left un-widened, since three short related
checkboxes on one row is a reasonable compact pattern, not clutter. Also added blank
full-width `description`-type spacer rows between logical sub-groups (position/alignment → font
→ colors/display-format → owner toggle → list settings) so the panel reads as sections.

**Immediate follow-up (still v0.6.2→v0.6.3)**: all-`width="full"` made it look worse, not
better — every single control on its own line is its own kind of clutter. Correct read of the
original ask: *pair* specific related controls on one row, not make everything full-width.
Switched those specific controls to AceConfigDialog's `width = "relative"` + `relWidth = 1/N`
(confirmed in the vendored `AceConfigDialog-3.0` source — `control:SetRelativeWidth(relWidth)`,
an exact fraction of the row, unlike `"half"`/`"double"`/plain numbers which are multiples of a
fixed "normal" unit and don't reliably give an exact 1/N split):
- X offset / Y offset / Text alignment — 3 on one row (1/3 each).
- Font / Font size — 2 on one row (1/2 each).
- Color (tanking) / Color (not tanking) — 2 on one row.
- Display format / Display threat owner — 2 on one row.
- Target-of-target's Color by class / Color — 2 on one row.
Everything else (list mode and its sub-options, the headers, the spacers between groups) stays
full-width/as before — not part of what was asked, left alone.

### v0.6.4: "Players shown" is now a slider, not a dropdown

Changed `listCount` from `type = "select"` (values 1/2/3) to `type = "range", min = 1, max = 3,
step = 1`, per request — purely a control-type swap, no change to the underlying value or
behavior. Also clarified for the user why "Display threat owner" hides itself in list mode: by
design, not a bug — the option is single-display-only since list mode already shows multiple
names/values at once, so a single "who owns threat" prefix doesn't map cleanly onto it. Not
changed; flagged as something to revisit (e.g. highlighting the owner's row in the list) if the
user wants it later.

### v0.7.0: player list rebuilt — rank by status, not raw threat

Confirmed by the user: list mode never showed more than one row, regardless of the configured
count. This answers the open question left at the end of the v0.6.1 entry above — true
magnitude-ranking by raw threat does not work on this client in practice. Raw threat
(`UnitDetailedThreatSituation`'s `raw`/`scaled` returns) came back secret for every group
member, every time, so `CollectThreatEntries` always found zero or one readable member and
either fell back to the single-value display or rendered a "list" of exactly one row.

**Rebuilt the ranking key**: instead of sorting by raw threat, `CollectThreatRows` now sorts by
`UnitThreatSituation(member, mob)`'s status (0-3) — the same function the Low/Medium/High
fallback and the single-display color logic already lean on throughout this file, and which has
been reliably readable everywhere else. A member is included if `Readable(status)`; once
included, `status` is *known* non-secret, so sorting by it and deriving `isTanking = status >= 2`
for row coloring are both safe ordinary Lua operations — no `issecretvalue()` dance needed for
those two things anymore.

The per-row *value* (what's actually displayed — raw/percentage per the display-format setting)
is a separate concern from ranking, and still goes through the widget-sink technique: fetched
fresh per row via `UnitDetailedThreatSituation(row.unit, mob)` and hand straight to
`text:SetFormattedText(...)`, since it can be secret even when that row's `status` isn't. One
subtlety this introduced: `SetFormattedText` errors on a genuinely-`nil` argument (unlike a
secret one, which it accepts fine) — a row whose raw/scaled value comes back `nil` (truly
absent, not secret — rare but distinct) is now skipped via a `type(...) == "number"` check
before being added to the output, rather than risking a crash.

Net effect: the list should now actually rank and show multiple real rows whenever multiple
group members have any registered threat on the unit — genuinely different from v0.6.x, not
just a bigger fallback. Not yet confirmed against a live multi-member pull.

### v0.8.0: background, "when showing 1 player" choice, lower-row size

Three additions requested together, planned with the user before implementing (confirmed) —
each is small on its own but together forced a structural change to how the player list
renders.

**Background** (`bgEnabled` toggle + `bgColor`, a single color-with-alpha picker rather than
two separate controls — AceConfig's color widget natively supports a 4th alpha channel via
`hasAlpha = true`, so one swatch does both). Originally scoped to list mode only in the initial
plan; widened on request to also cover the single-value display, since the user wanted it
"also... for only my own threat." Implemented as one `Texture` widget per nameplate
(`widgets.threatBg`), shown by `ApplyBackground(bg, enabled, color, firstWidget, lastWidget)` —
anchored to whichever widget(s) actually rendered (the single `threatText`, or the first/last
of the list's row stack) with a small padding, rather than computing a size itself. This is why
`ApplyThreatDisplay` now returns `(success, firstWidget, lastWidget)` instead of just a boolean
— `UpdatePlate` needs to know which widgets to span.

**"When showing 1 player": My Threat / Top Threat** (`soloListMode`, select, default `"mine"`)
— only shown in options when `listMode` is on and `listCount == 1`, since that's the only case
where it's ambiguous whose number is on screen. "My Threat" doesn't touch the ranking logic at
all — it's implemented as literally the same code path as list mode being off
(`ApplyThreatSingle`), reused directly. "Top Threat" is what `listCount == 1` already did before
this setting existed (row 1 of the ranked list, whoever that is).

**Lower row size** (`secondaryScale`, range 50-100%, default 100 = no change) — shrinks rows
below #1 in the list relative to the configured font size. This is the one that forced a real
architecture change: **WoW's FontString has no way to mix font sizes within one block of
text**, so the player list could no longer be a single multi-line `SetFormattedText` call (how
it worked through v0.7.0) — it's now a small pool of independent FontString widgets,
`widgets.listRows[1..3]`, created lazily (`EnsureListRow`) and stacked vertically
(`PositionListRow`, anchoring each row's top edge to the previous row's bottom edge using
whichever point pair matches the configured horizontal alignment). Each row still gets its own
name/value coloring the same way as before (embedded `|cff...|r` codes within that one row's
own `SetFormattedText` call — the per-row value can still be secret, still goes through the
sink). `ApplyThreatList` now returns `(success, firstWidget, lastWidget)` — the first and last
*row* widgets — for the background to span.

**Bug caught while building this**: moving widget-creation/positioning helpers
(`EnsureListRow`, `ResolveFontPath`, `PositionListRow`, `ApplyBackground`) into the file without
also moving them *before* the "Player list mode" section that calls them left a forward
reference — in Lua, a `local function` defined later in a chunk is not yet an upvalue for code
defined earlier, so the call would have resolved to a nil global at runtime. Fixed by moving the
whole "Widget lifecycle" section to before "Player list mode" in file order. Caught and fixed
before deploying, not after — worth remembering as a checklist item ("did I define this helper
before everything that calls it?") any time functions move between sections of this file again.

Not yet confirmed in-game as of this writing (deployed, not yet tested by the user).

### v0.9.0: Debug Mode — fake preview data for testing appearance

Requested so the user could check how settings look (colors, background, row scaling,
alignment) without needing a real pull. Planned with the user before coding (confirmed: every
nameplate not just enemies, fake both target-of-target and threat, names stable with values
re-rolling each tick) — see the plan laid out in conversation prior to this entry.

**Design decision**: implemented as a fully separate rendering path
(`RenderDebugPreview`/`RollDebugRoster`/`EnsureDebugRoster` in ThreatMeterNP.lua), not by
threading fake values through `ApplyExactThreatPercentage`/`ApplyThreatList`/`CollectThreatRows`
etc. Reasoning: fake values are plain Lua numbers that are never secret, so none of the
real path's secret-value handling applies or is needed; keeping debug entirely separate means
zero risk of a debug-mode code change accidentally breaking the real, already-validated
data path. The one piece of real rendering code it *does* reuse directly is `RenderListRow`
(extracted from inside `ApplyThreatList` specifically to make this possible) — so the debug
list and the real list are guaranteed to look pixel-identical for the same settings; only
where `name`/`isTanking`/`raw`/`scaled` came from differs between the two callers.

**`GetClassColorRGB` refactor**: split into `GetClassColorRGBByFilename(classFilename)` (the
actual color lookup, shared) and `GetClassColorRGB(unitToken)` (resolves a real unit's class
then delegates) — needed because the debug roster has fabricated classes with no real unit
token to call `UnitClass` on.

**Roster**: `DEBUG_ROSTER_POOL`, 8 fixed name/class pairs (one of each basic class family for
varied class-color testing). `EnsureDebugRoster()` copies it into a working `debugRoster` table
once per session (lazy, first time debug mode actually renders); names/classes never change
again that session. `RollDebugRoster()` re-randomizes each member's `status` (0-3, also used to
derive `isTanking = status >= 2`), `raw` (500-50000), and `scaled` (10-150) — called once per
*plate* per tick (not once per tick total), so with multiple nameplates on screen each one
shows its own independent-looking snapshot even though they share the same underlying roster
table (safe because each call rolls then immediately renders before the next plate's call
rolls again).

**Hook point**: `UpdatePlate` checks `profile.debugMode` immediately after the basic
`UnitExists` check and before the real enemy-only/visibility checks — so debug mode applies to
literally every tracked nameplate (friendly, neutral, hostile) regardless of group status,
which is already how every nameplate gets tracked internally (the real eligibility filtering
normally happens *inside* `UpdatePlate`, not at the tracking stage).

**UI**: new "Debug" options group (its own section, separate from Target of Target/Threat,
since it affects both), one toggle, with an explicit warning in its tooltip that it shows fake
data and should be turned off before actually playing.

Not yet tested in-game by the user as of this writing.

### v0.9.1: renamed ThreatWatch → ThreatMeterNP

Picked through a short naming brainstorm in conversation (not recorded step-by-step here) —
landed on **ThreatMeterNP**: keeps "Threat," reuses the established "threat meter" term so it
reads instantly familiar, and "NP" (nameplate) makes the placement explicit, matching a known
WoW addon-naming shorthand (Kui Nameplates, NeatPlates). Earlier candidates considered and
rejected: AggroWatch/PlateWatch/PlateIntel (liked the shape, didn't explicitly signal
nameplates), ThreatWatchPlates/PlateThreatWatch (too long), ThreatListNP (named only the
optional list-display mode, not the single-value default).

**What actually changed** — this was a pure rename with no functional/behavioral change:
- Folder: `ThreatWatch/` → `ThreatMeterNP/`. Main engine file renamed to match:
  `ThreatWatch.lua` → `ThreatMeterNP.lua`. `Options.lua` kept its name (already generic).
- `.toc`: renamed to `ThreatMeterNP.toc`; `## Title:`, `## SavedVariables:` updated.
- Every occurrence of the Lua identifier `ThreatWatch` (the global AceAddon object used
  throughout both files — `ThreatWatch.db.profile...`, `ThreatWatch:RefreshAllWidgets()`, the
  `NewAddon(...)` call, AceConfig/LibDataBroker/LibDBIcon registration keys, the minimap icon's
  texture path) replaced with `ThreatMeterNP` via a straight text substitution — safe because
  every literal occurrence of that exact string in the source was addon-identity-related, none
  of it collided with an unrelated word.
- Slash commands: `/threatwatch`/`/tw` → `/threatmeternp`/`/tmnp` (lowercase strings, so the
  identifier substitution above didn't touch them — fixed by hand).
- `Deploy-ThreatWatch.bat`/`Package-ThreatWatch.bat` → `Deploy-ThreatMeterNP.bat`/
  `Package-ThreatMeterNP.bat`, with their internal `SOURCE_DIR`/`DEST_DIR`/`.toc` filename/zip
  naming references updated to match.
- Old `ThreatWatch` folder removed from both the repo and the deployed client AddOns folder
  (to avoid a stale duplicate addon showing up in-game), replaced by the new deploy.
- This file, README.md, and infos.md: bulk text-replaced `ThreatWatch` → `ThreatMeterNP`
  throughout (every mention was the addon's name, nothing else used that string), then this
  top section and this entry were written by hand afterward specifically to preserve the
  rename history accurately — a blind bulk replace alone would have erased the fact that the
  addon was ever called ThreatWatch at all.

**SavedVariables migration** (the one part of this that could have silently lost user data):
the SavedVariables key is tied to the addon's name
(`## SavedVariables: ThreatWatchDB` → `...ThreatMeterNPDB`), and WoW has no built-in way to
carry a global table forward under a new name — without doing something about it, renaming
would have silently reset every setting to defaults on first load post-rename. Fixed with a
one-time shim at the top of `OnInitialize`, before `AceDB-3.0:New(...)` runs:
```lua
if not ThreatMeterNPDB and ThreatWatchDB then
    ThreatMeterNPDB = ThreatWatchDB
end
```
Copies the whole old global table over by reference the first time the renamed addon loads;
does nothing on every load after, since `ThreatMeterNPDB` exists by then. Not yet confirmed
in-game that this actually preserved the user's existing settings — worth checking after the
first `/reload` post-rename.

### v0.9.2: migration shim removed, "Show Target of target" toggle added

**Migration shim removed**: the one-time `ThreatWatchDB` → `ThreatMeterNPDB` copy added in
v0.9.1 (above) has served its purpose and was deleted from `OnInitialize` on request — it was
always meant to be temporary (every load after the first no-op'd anyway, since
`ThreatMeterNPDB` exists by then).

**New toggle**: `targetOfTarget.enabled` (default `true`), a "Show Target of target" checkbox
— the first row in that label's options, full-width, right under the header. Implemented by
adding an optional 6th parameter to `LabelOptions` (`includeEnabledToggle`), passed `true` only
for the target-of-target call site in `BuildOptions` (not threat — wasn't asked for there, and
threat already has its own always-on fallback chain that doesn't need an equivalent kill
switch). Wired into both render paths: the real `UpdatePlate` (added to the existing
`UnitExists(totToken)` condition so the label simply doesn't show when off) and
`RenderDebugPreview` (wrapped in its own `if totSettings.enabled then ... else
widgets.totText:Hide() end`, so the debug preview respects the setting too rather than always
showing a fake target-of-target regardless).

### v0.9.3: "Show Threat" toggle added too

Follow-up request: the same on/off toggle for the Threat label. `threat.enabled` (default
`true`), wired identically to target-of-target's: `LabelOptions` called with
`includeEnabledToggle = true` for the threat group too (`BuildOptions`), and both render paths
(`UpdatePlate`, `RenderDebugPreview`) wrap their *entire* threat block — single display, list
rows, and background — in `if profile.threat.enabled then ... else` (hide `threatText`, hide
every list row via `HideListRows`, hide `threatBg`) `end`. Unlike target-of-target's toggle,
this one has to gate three different widgets (not just one FontString) since threat can be
rendered as a single value, a multi-row list, or neither, plus its optional background.

### v0.9.4: fix — threat (and target-of-target) stopped showing on existing profiles

Reported by the user immediately after v0.9.3: threat disappeared entirely. Root cause: both
`enabled` checks (`if profile.threat.enabled then`, and the same pattern added for
target-of-target in v0.9.2) trusted AceDB-3.0 to supply the `true` default for a key that
didn't exist yet in the user's *already-populated* `profile.threat`/`profile.targetOfTarget`
sub-tables. Checked the actual SavedVariables file on disk to confirm: `enabled` wasn't
physically present there, and neither were several other settings added in earlier versions
(`bgEnabled`, `secondaryScale`, `soloListMode`, `showOwner`, `listColorByClass`) — AceDB's
default-filling is a lazy fallback, not a retroactive write into existing nested tables. Those
earlier settings never surfaced this as a bug because their *consuming code* already read them
with an explicit `or <default>` (e.g. `GetDisplayFormat`'s `profile.threat.displayFormat or 2`,
`profile.listCount or 3`) — a value of `nil` and the intended default produced identical
behavior. The two new `enabled` checks had no such fallback and read `nil` directly as "off."

**Fix**: changed all four `enabled` checks (`UpdatePlate` ×2, `RenderDebugPreview` ×2) from
bare truthiness to `~= false` — "on unless explicitly set to false," which treats an unset
value the same as the intended `true` default regardless of whether AceDB ever backfills it.

### v0.9.5: fix — options panel checkbox showed unchecked despite the label actually showing

Follow-up to v0.9.4: the engine now correctly treats an unset `enabled` as "on," but the
options panel's checkbox `get` was still the plain `ValueGet`, which returns the raw stored
value (`nil`) — AceGUI renders that as unchecked, a visible mismatch against the label that's
actually showing. Fixed by wrapping the checkbox's `get` to also apply `~= false` (`local
rawGet = ValueGet(...); get = function(...) return rawGet(...) ~= false end`), while `set`
still writes the literal boolean the user picks, same as before.

### v0.9.6: fix — single threat display invisible when list mode was off

Reported by the user: "if you select show player list instead of your own threat, the list
works. If you check it off, it displays the background selected, but does not show your
threat." Root cause traced to the v0.8.0 background refactor (above): before that refactor,
`UpdatePlate` itself called `widgets.threatText:Show()`/`:Hide()` based on
`ApplyThreatDisplay`'s boolean return. When that refactor changed `ApplyThreatDisplay` to
return `(success, firstWidget, lastWidget)` for the background to span, the call site started
discarding the success boolean (`local _, first, last = ApplyThreatDisplay(...)`) and the
explicit `:Show()` was never relocated into the single-display path itself. List mode's own
`RenderListRow` already calls `rowWidget:Show()` internally, and the debug preview's
single-display branch already calls `widgets.threatText:Show()` too — only the real
single-display chain (`ApplyThreatSingle` → `ApplyExactThreatPercentage`/
`ApplyThreatLevelFallback`) was missing it. Since a FontString starts hidden
(`CreateLabel`) and nothing else was telling it to appear, the background (anchored correctly
to `widgets.threatText` either way) rendered while the text itself stayed invisible.

**Fix**: `ApplyThreatSingle` now calls `widgets.threatText:Show()` itself right after either
underlying function succeeds, mirroring the pattern the list and debug paths already used.

### v0.9.7: player list — name uses the threat color when class coloring is off

Per request: when "Color name by class" (`listColorByClass`) is off, a row's name was always
plain white (`nr, ng, nb = 1, 1, 1`), independent of that row's own tanking/not-tanking value
color. Changed so the name falls back to the same `colorTanking`/`colorNotTanking` color
already used for the value, instead of white. Implemented in `RenderListRow` itself — the
shared renderer for both the real list (`ApplyThreatList`) and the debug preview
(`RenderDebugPreview`) — rather than in each caller, so both stay pixel-identical. Both call
sites now pass `nr` (and `ng`/`nb`) as `nil` unless class coloring actually resolved a color;
`RenderListRow` fills in the threat color whenever `nr` comes in `nil`.

### v0.9.8: fix — player list background width ignored secondaryScale, overlapping row 1

Reported by the user: with multiple players shown and "Lower row size" set to 80%, the
background's width was sometimes wrong and row 1 (full size) could overlap/overflow it.

Root cause: `ApplyBackground` sized its left/right edges from `firstWidget` (row 1) and
`lastWidget` (the last row) only — correct for the *vertical* span (rows stack top-to-bottom
in rank order, so first is always topmost and last always bottommost), but wrong
*horizontally*, since each row's rendered width varies independently of its rank once
`secondaryScale` shrinks every row after #1. Whichever row happens to render the widest text
(not necessarily row 1 or the last row — depends on name length and value digits per row) was
never consulted, so the background could end up narrower than that row's actual text.

**Fix**: `ApplyThreatList` (real list) and `RenderDebugPreview`'s list branch (fake preview)
now track whichever rendered row has the greatest `:GetStringWidth()` as they go, and return
it as a third/fourth widget alongside first/last. `ApplyBackground` takes this as an optional
`widestWidget` parameter and anchors its `LEFT`/`RIGHT` edges to it instead of to
`firstWidget`/`lastWidget` (still using `firstWidget`'s `TOP` and `lastWidget`'s `BOTTOM` for
the vertical span, which was never the problem). Using the single widest row for *both*
horizontal edges works regardless of the configured text alignment: Left/Right-aligned rows
already share an identical left/right x across the whole stack (per `STACK_POINTS`), so only
the far edge differs by width; Center-aligned rows share the same horizontal center, so the
widest row's left and right edges are, by construction, the furthest-out on both sides.
`ApplyThreatDisplay`'s return signature grew a fourth value (`widestWidget`) to carry this
from `ApplyThreatList` up to `UpdatePlate`; the single-display path simply returns
`widgets.threatText` for all three (first/last/widest), since there's only one widget.

### v1.0: first stable release

Flagged by the user right after the v0.9.8 fix above — `.toc` `## Version:` set to `1.0`
(previous versions were `0.x` pre-release increments). No functional change from v0.9.8;
purely a version-number/status flip marking the addon as its first stable release.

### Default values (v2 base defaults, not SavedVariables)

Set directly in `Options.lua`'s `defaults` table — these are what a fresh install (or a wiped
profile) starts with, distinct from whatever ends up in `ThreatMeterNPDB` once a user has touched
the options panel:

- Target of target: X offset `0`, Y offset `-28`, font `"Arial Narrow"` (an LSM-registered
  font name — the request said "Arrial Narrow," corrected the spelling so `LSM:Fetch` actually
  resolves it instead of silently falling back to the default font).
- Threat: X offset `74`, Y offset `0`, font size `12`.
- Everything not explicitly listed here (threat font, both label's unlisted fields) keeps its
  original v2 default.
