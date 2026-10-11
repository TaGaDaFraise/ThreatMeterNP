# infos.md — scanned addon/API knowledge cache

Purpose: avoid re-scanning the WoW client / API dump each session. Append new findings under
the relevant section instead of re-discovering them. Each entry notes the source path so it
can be re-verified if the client updates.

## Windows batch gotchas hit while building this repo's scripts

- `findstr` splits a search string **on spaces into multiple OR'd terms by default** — e.g.
  `findstr /b "## Version:" file` does NOT match the literal line `## Version:`, it matches any
  line starting with `##` OR containing `Version:` (nearly every line in a `.toc`). Must use
  `findstr /b /c:"## Version:" file` (`/c:"..."` forces one literal search string) to match a
  multi-word literal. Bit this while writing `Package-ThreatMeterNP.bat`'s version-from-.toc
  parser — first attempt silently grabbed the wrong line and produced `ThreatMeterNP-0.zip`
  instead of `ThreatMeterNP-0.1.0.zip`.
- `Compress-Archive -Path <folder>` (PowerShell, invoked from `.bat` via
  `powershell -NoProfile -Command "..."`) zips the folder **with itself as the top-level entry**
  — i.e. zipping `...\ThreatMeterNP` produces a zip containing `ThreatMeterNP\ThreatMeterNP.toc` etc.
  at the right nesting for a straight AddOns-folder drop. Confirmed by extracting and checking
  — no extra flag needed to get that structure.

## Vendoring Ace3 + companion libraries for v2

For the v2 options panel/minimap button/SavedVariables (requirements.md §13), vendored
libraries directly from **`Plater/libs/`** in the local WoW Forever Beta client
(`D:\World of Warcraft\_classic_beta_\Interface\AddOns\Plater\libs\`) rather than fetching
fresh copies — that exact copy is already proven to load on this client's non-standard
interface number (16001), sidestepping any version-compat guessing. Plater's `libs\libs.xml`
is the reference load order (`LibStub` first, `AceGUI-3.0` before `AceConfig-3.0` since
`AceConfigDialog-3.0` expects `AceGUI-3.0` already registered, everything else via LibStub's
lazy `GetLibrary` so exact order matters less once LibStub itself is first).

Libraries actually used (trimmed down from Plater's fuller set — Plater also carries
AceComm/AceTimer/AceLocale/AceSerializer/LibCompress/LibDeflate/LibCustomGlow/
LibRangeCheck/LibTranslit/DF(Details Framework), none of which ThreatMeterNP needs):
`LibStub`, `CallbackHandler-1.0`, `AceAddon-3.0`, `AceConsole-3.0` (slash commands), `AceDB-3.0`
(SavedVariables), `AceConfig-3.0` (bundles `AceConfigRegistry-3.0`/`AceConfigCmd-3.0`/
`AceConfigDialog-3.0` internally — a single `<Include>` of `AceConfig-3.0\AceConfig-3.0.xml`
pulls in all three), `AceGUI-3.0` (widgets AceConfigDialog renders with), `LibSharedMedia-3.0`
(font dropdown source), `LibDataBroker-1.1` + `LibDBIcon-1.0` (minimap button).

Icon: `BugSack/Media/icon.tga` (also local, correctly-sized minimap-icon art) — explicitly a
placeholder, see requirements.md §13.

Practical API notes from building this:
- `LSM:Fetch(mediatype, name)` resolves a registered display **name** to an actual file path;
  `LSM:GetDefault(mediatype)` returns a **name**, not a path — feeding `GetDefault`'s result
  straight into `SetFont` is a bug (looks like a path, isn't one). Always route both through
  `Fetch`.
- `AceDB-3.0:New(savedVariablesGlobalName, defaults, true)` — the third arg `true` makes AceDB
  use one shared "Default" profile for every character on the account rather than per-character
  profiles. This is what "account-wide settings" means in AceDB terms; no separate
  profile-switching UI needed for that behavior.
- `LibStub("AceConfigDialog-3.0"):Open(appName)` pops the standalone Ace3 options window
  directly — simpler and more version-portable across this multi-flavor custom client than
  relying on Blizzard's Settings/InterfaceOptions API integration alone (`AddToBlizOptions` is
  still worth calling too, for the Blizzard AddOns-list entry, but `Open` is the reliable path
  for a minimap-click / slash-command handler).

## This repo's own layout

- `ThreatMeterNP/` — the addon source (`ThreatMeterNP.toc`, `ThreatMeterNP.lua`). This is what gets
  deployed into a WoW client's `Interface\AddOns\` folder.
- `Deploy-ThreatMeterNP.bat` — copies `ThreatMeterNP/` into the client configured by its
  `WOW_ADDONS_DIR` variable (defaults to the WoW Forever Beta client below). Edit that
  variable, don't hardcode a new path elsewhere.
- `requirements.md` — spec, decisions, and open assumptions.
- `README.md` — GitHub/CurseForge-facing project description.

## Local environment map

- Multiple WoW clients live under `D:\World of Warcraft\`:
  `_retail_`, `_classic_`, `_classic_era_`, `_classic_ptr_`, `_classic_beta_`, `_anniversary_`.
- **"WoW Forever" = `D:\World of Warcraft\_classic_beta_`.** This is the client that actually
  has `Plater` and `PlaterTOT` installed under `Interface\AddOns\`. It's a merged-expansion
  private-server-style client — its addon TOCs list many `## Interface:` versions at once
  (e.g. PlaterTOT's TOC lists 120005, 110207, 50503, 40402, 30405, 20505, 11508 …), so don't
  assume single-expansion API behavior.
- Lua API reference dump: `C:\Repo\wow\lua\API\Wow Forever\BlizzardInterfaceCode\` — this is
  Blizzard's own interface code, including
  `Interface\AddOns\Blizzard_APIDocumentationGenerated\*Documentation.lua`, which has
  machine-readable function signatures (args/returns/flags). Prefer grepping these
  `*Documentation.lua` files for exact signatures over guessing from memory.
  - `UnitDocumentation.lua` — Unit* API (threat, health, etc.)
  - `NamePlateDocumentation.lua` / `NamePlateManagerDocumentation.lua` — C_NamePlate API
  - `Blizzard_NamePlates\Blizzard_NamePlates.lua` — default nameplate frame implementation
  - `Blizzard_UnitFrame\Shared\CompactUnitFrame.lua` / `Mainline\UnitFrame.lua` — unit frame internals

## Plater (nameplate addon) — installed copy

Path: `D:\World of Warcraft\_classic_beta_\Interface\AddOns\Plater\`

- Multiple `.toc` variants per expansion flavor (`Plater_Vanilla.toc`, `Plater_TBC.toc`,
  `Plater_Mists.toc`, `Plater_Mainline.toc`, `Plater_Camelot.toc`) — same core Lua files, just
  different `## Interface:` targeting.
- Key files if we ever need Plater's *internal* scripting/mod system (hook-based scripts users
  import as strings, run inside Plater's own sandbox):
  - `Plater_ScriptingOptions.lua`, `Plater_ScriptingPanels.lua`, `Plater_ScriptLibrary.lua`,
    `Plater_Script_Include.lua`, `Plater_ScriptHelpers.lua` — the mod/script system (hook types
    like Constructor/Updater/OnUpdate, `Plater.ScriptMetaFunctions`, `HOOK_MOD_OPTION_CHANGED`, etc.)
  - `Plater_API.lua` — public helper API surface exposed to scripts/other addons.
  - `Plater_Data.lua` — unit frame structural definitions.
- **Decision for this project: we are NOT using Plater's internal script/mod system.** See
  PlaterTOT below — going through the standalone-addon route with `Plater.Dependencies` is
  simpler, doesn't require learning Plater's script sandbox, and survives Plater updates better.

## PlaterTOT — reference implementation (standalone addon riding on Plater)

Path: `D:\World of Warcraft\_classic_beta_\Interface\AddOns\PlaterTOT\`

This is a real, working, local example of **exactly the kind of addon we're building**: a
standalone addon that depends on Plater and attaches extra widgets to Plater's nameplate
frames without modifying Plater itself. Use it as the structural template.

### .toc pattern (confirmed from `PlaterTOT.toc`)
```
## Interface: 120005, 110207, 50503, 40402, 30405, 20505, 11508   (multi-flavor; pick ours per client)
## Title: PlaterTOT
## Dependencies: Plater        <- hard dependency, addon won't load without Plater enabled
## SavedVariables: PlaterTOTDB
## LoadOnDemand: 0
## DefaultState: Enabled
<file list, one per line, load order matters>
```

### Core attach pattern (confirmed from `PlaterTOT.lua`)
1. Create a driver frame, register events on it directly (not via Plater's script system):
   `NAME_PLATE_UNIT_ADDED`, `NAME_PLATE_UNIT_REMOVED`, plus whatever data-change events are
   needed (PlaterTOT also listens to `UNIT_HEALTH`, `UNIT_AURA`, `PLAYER_TARGET_CHANGED`, etc.
   — wrapped in `pcall` for events that may not exist on every client flavor).
2. On `NAME_PLATE_UNIT_ADDED`, resolve the Plater nameplate frame:
   `local plate = C_NamePlate.GetNamePlateForUnit(unitToken)`
   then reach the actual Plater unit frame via `plate.unitFrame` and its health bar via
   `plate.unitFrame.healthBar`.
3. Lazily construct our own child frame/fontstring the first time we see a plate
   (`ensureTOTOnPlate(plate, unitToken)` pattern): `CreateFrame("Frame", nil, healthBar)`, then
   `frame:CreateFontString(nil, "overlay", "GameFontNormalSmall")`, `SetFont`, `SetPoint`,
   store the widget on the health bar itself (e.g. `healthBar.PlaterTOT_Text = tot`) so it's
   found instantly next time instead of recreated.
4. Keep a `unitToPlate[unitToken] = plate` lookup table to resolve plates fast on subsequent
   update events without re-querying `C_NamePlate`.
5. On `NAME_PLATE_UNIT_REMOVED`, hide (not destroy) the widgets — frames get reused by Blizzard's
   nameplate pool, so hiding + re-populating on next ADDED is the correct lifecycle, not
   recreating.
6. Also hooks `hooksecurefunc(Plater, "UpdatePlateSize", ...)` to reposition/rescale custom
   widgets whenever Plater resizes a plate (important for keeping custom text anchored
   correctly when Plater's own scaling logic runs).
7. There's also a periodic full-resync helper (`syncNameplatesToPlaterTOT`, iterates
   `C_NamePlate.GetNamePlates()`) used e.g. after zoning, as a safety net in case an ADDED event
   was missed.

### Relevant for our addon specifically
- Target-of-target display: PlaterTOT already solves this exact sub-problem (see
  `ensureTOTOnPlate` / the `tot` fontstring, and the older WeakAura snippet in
  requirements.md using `UnitName(unitToken.."-target")` — same trick: append `-target` to a
  unit token to get its target, e.g. `unitToken.."-target"`).
- Threat display: PlaterTOT does **not** implement this (it's TOT/aura/class-specific only) —
  our threat-number widget is new work, not something to copy from PlaterTOT directly, but the
  widget-attach/lifecycle pattern above applies identically.

## WoW API — confirmed signatures (from `UnitDocumentation.lua`, `NamePlateDocumentation.lua`)

### `UnitDetailedThreatSituation(unit, mobGUID)`
- Returns: `isTanking (bool), status (number), scaledPercentage (number), rawPercentage (number), rawThreat (number)`
- Flagged `SecretWhenUnitThreatValuesRestricted = true` — in some restricted content (e.g.
  Mythic+ in retail-flavored rulesets) `rawThreat`/percentages may come back as a "secret"
  value that can't be read/printed directly by addon code. Need to test in practice on this
  client; may need to only display `scaledPercentage`/`rawPercentage` if raw value is blocked,
  or handle a nil/secret gracefully.
- Usage for our case: call as `UnitDetailedThreatSituation("player", unitToken)` per nameplate
  unit to get our own threat standing on that mob.

### Target-of-target unit token trick
- Correct raw-API form: `UnitName(unitToken.."target")`, `UnitExists(unitToken.."target")` —
  **no separator**. Standard Blizzard unit-token suffix chaining never uses a dash (this is
  the same mechanism behind `targettarget`, `focustarget`, `party1target`, etc.).
- The WeakAura snippet in requirements.md uses `aura_env.region.cloneId.."-target"` — **that
  dash is WeakAuras-specific sugar** (its own custom unit-token resolver inside `aura_env`),
  not a raw Blizzard API convention. Copying it verbatim into plain addon Lua would silently
  produce an invalid/non-existent unit token. Caught this while implementing ThreatMeterNP —
  worth remembering for any future WeakAuras-snippet-to-addon port.

### Nameplate frame's own unit token field
- The base nameplate frame mixin (`NamePlateBaseMixin:SetUnit`, in
  `Blizzard_NamePlates\Blizzard_NamePlateBase.lua`) stores the unit token as **`self.unitToken`**
  — i.e. `plate.unitToken`, not `plate.namePlateUnitToken` (a plausible-looking but wrong
  guess). Use `plate.unitToken` when resyncing from `C_NamePlate.GetNamePlates()` without an
  event argument to hand you the token directly.

### "Secret values" — the security system that blocks raw threat comparisons

Hit this live while testing ThreatMeterNP: comparing one unit's raw threat number against
another's threw `attempt to compare local 'threat' (a secret number value, while execution
tainted by 'ThreatMeterNP')`. This is a real, documented Blizzard security system, not a client
quirk — confirmed via `SecretPredicatesDocumentation.lua`, `SecretPredicateAPIDocumentation.lua`,
`LuaValuePredicatesDocumentation.lua` in the API dump.

- Certain API return values (threat numbers among them, flagged per-function as e.g.
  `SecretWhenUnitThreatValuesRestricted = true` in `UnitDocumentation.lua`) can come back as
  **"secret" values**: opaque wrappers the game engine hands to addon code specifically to
  prevent reading/comparing the underlying magnitude, most likely an anti-cheat / anti-parsing
  measure.
- **`type(secretValue)` still returns the real underlying type** — `"number"` for a secret
  number, but also **`"boolean"` for a secret boolean**. You cannot detect secrecy by
  type-checking, for either type. Confirmed both in practice: `UnitDetailedThreatSituation`'s
  `rawThreat` (number) and its `isTanking` (boolean, first return) each independently came back
  secret and threw — the boolean case throws on a plain `if secretBool then` ("attempt to
  perform boolean test on ... a secret boolean value"), not just on `>`/arithmetic. **Any**
  value from one of these APIs needs the guard before it's used for anything beyond
  storing/passing through, regardless of its type.
- The dedicated predicate is the global function **`issecretvalue(value)`** (confirmed via
  `FrameScriptDocumentation.lua`: `Documentation = { "Returns true if a supplied value is a
  secret value." }`, and seen in real use in `Blizzard_EventTrace.lua`:
  `if showSecretValues and issecretvalue(arg) then`). Always gate with `issecretvalue()` before
  a comparison, arithmetic, *or* a boolean test — touching one the wrong way throws, it does
  not just silently misbehave.
- A `X and not issecretvalue(X)` guard is *itself* safe to call on a secret value — calling
  `type()`/`issecretvalue()` on one, or just storing/returning it, does not throw. Only
  operators that need to read the underlying magnitude/truth (`>`, `<`, `==`, arithmetic, `if`)
  throw.
- Empirically, in this "WoW Forever" client, **`UnitDetailedThreatSituation("player", unit)`'s
  `rawThreat` came back secret even solo, outside any instance** — despite the predicate's own
  doc text suggesting a player-vs-nameplate query should "generally not be secret." Don't trust
  that doc caveat as a guarantee on this client; always guard with `issecretvalue()` regardless
  of what the predicate description implies should be safe.
- **Bug this caused**: an `IsUsableNumber` check written as `type(value) == "number"` silently
  let secret values through, which then crashed on the first `>` comparison inside a `pairs()`
  update loop — aborting that whole loop iteration and starving every nameplate after the first
  one in iteration order. One unguarded secret value can look like "only the first item in the
  loop updates," which is a confusing symptom pointing away from the real cause. Lesson: wrap
  per-item work in a polling/update loop with `pcall` (see ThreatMeterNP's `OnUpdate` handler) so
  one bad item can't starve the rest, regardless of the root cause.
- **Sanctioned fallback**: Blizzard's own default unit frames don't do this raw comparison
  themselves — `CompactUnitFrame.lua`'s aggro-highlight logic calls **`UnitThreatSituation(unit,
  [mobGUID])`** and **`UnitThreatLeadSituation(unit, mobGUID)`** instead, which return small
  pre-computed integers (`UnitThreatLeadSituation`: 0-3, "how far above the #2 threat holder,
  always 3/red if not first") computed engine-side, handed to addons already reduced to a safe
  category — no addon-side comparison needed. These carry a narrower secrecy predicate
  (`SecretWhenUnitThreatStateRestricted`) than raw values. Confirmed present in this client's
  `UnitDocumentation.lua`. **Use these as the fallback when a raw-value comparison approach
  comes back secret**, rather than leaving the feature silently blank.

### Nameplate lifecycle
- Events: `NAME_PLATE_UNIT_ADDED`, `NAME_PLATE_UNIT_REMOVED` — fire with `unitToken` as the
  event arg. Confirmed present in `Blizzard_NamePlates.lua`, `NamePlateDocumentation.lua`.
- `C_NamePlate.GetNamePlateForUnit(unitToken)` — returns the plate frame (has `.unitFrame`).
- `C_NamePlate.GetNamePlates()` — returns array of all current plates, for resync sweeps.

## "WoW Forever" client identity — confirmed interface version

- `D:\World of Warcraft\.build.info` lists product `wow_classic_beta` at **Version `1.60.1.69913`**.
  That converts to TOC `## Interface: 16001` (major*10000 + minor*100 + patch = 1*10000+60*100+1).
  This is **not a real Blizzard patch number** for any expansion — it's a custom versioning
  scheme used by this "WoW Forever" project (private/custom server occupying the `_classic_beta_`
  client slot).
- Confirmed: the installed `Plater\Plater.toc` (unsuffixed, default) and `Plater_Camelot.toc`
  both explicitly declare `## Interface: 16001` — i.e. **Plater's author has deliberately built
  a variant targeting this exact custom client.** Good signal that Plater itself is
  purpose-built for this project.
- **PlaterTOT has no such variant.** Its `.toc` (as downloaded from CurseForge/retail) lists
  `## Interface: 120005, 120001, 120000, 110207, 110200, 50503, 50502, 40402, 30405, 30404,
  38000, 20505, 20506, 11508, 11509` — **16001 is not in that list.** A retail copy of
  PlaterTOT dropped into this client will be flagged as out-of-date by the client's own TOC
  version check. Whether it still loads depends on the "Load out of date AddOns" account
  setting (not forced on or off in `WTF\Config.wtf` here — using client default). If it's
  loaded, PlaterTOT is running on unverified assumptions about this custom client's Plater
  build and backend API parity — static file inspection can't confirm the private server's
  backend actually implements every call (e.g. threat data) correctly; only an in-game test
  (with `!BugGrabber`/`BugSack`, both already installed, watched for Lua errors) can.
- Practical takeaway for a retail-sourced companion addon on this client: **check the TOC
  interface number first** (cheap, catches "won't even load" cases) — add `16001` to the
  `## Interface:` line if missing and the account isn't set to load out-of-date addons anyway.

### Blizzard's own "threatShowNumeric" technique — a second shot at real numbers

Investigated per user request ("look for threatshownumeric 1, look at ElvUI's threat meter")
after confirming the manual raw-threat-gap approach never produces usable values on this
client. Found in `Blizzard_UnitFrame\Mainline\UnitFrame.lua`:

- `## CVar threatShowNumeric`, checked via `ShowNumericThreat()` →
  `CVarCallbackRegistry:GetCVarValueBool("threatShowNumeric")` — the cvar that turns on
  Blizzard's own numeric threat % display on default unit frames.
- The actual data path, in `UnitFrame_UpdateThreatIndicator` (~line 1026-1044):
  ```lua
  local isTanking, detailedStatus, percentage, rawPercentage = UnitDetailedThreatSituation(indicator.feedbackUnit, indicator.unit);
  local display = rawPercentage;
  if ( isTanking ) then
      display = UnitThreatPercentageOfLead(indicator.feedbackUnit, indicator.unit);
  end
  ...
  numericIndicator.text:SetText(format("%1.0f", display).."%");
  ```
  i.e. **not tanking → `rawPercentage`** (`UnitDetailedThreatSituation`'s 4th return value);
  **tanking → a separate dedicated call, `UnitThreatPercentageOfLead`**. Notably does NOT use
  `rawThreat` (5th return, the value our original manual approach read and found secret) or
  `scaledPercentage` (3rd return) at all, and needs only a single two-unit query — no group
  iteration.
- **Not yet confirmed working or secret on this client** — implemented in ThreatMeterNP
  (`GetExactThreatPercentage` in ThreatMeterNP.lua) and deployed, but unlike the raw-gap approach
  this one was never specifically live-tested before shipping. `UnitThreatPercentageOfLead` is
  flagged with the same `SecretWhenUnitThreatValuesRestricted` predicate as the raw values that
  failed, so it may well also come back secret — but `rawPercentage` and `UnitThreatPercentageOfLead`
  are genuinely different return values/functions from the ones already proven secret, so it
  was worth an honest attempt rather than assuming failure. If it also comes back secret, the
  existing `issecretvalue()` guards catch it cleanly and the Low/Medium/High fallback still
  applies — no new crash risk either way.

### EllesmereUI — the actual breakthrough on exact threat numbers

User correction: the relevant addon was **EllesmereUI**, not ElvUI (easy to mishear) — a large
modular UI suite (`EllesmereUI`, `EllesmereUINameplates`, `EllesmereUIUnitFrames`,
`EllesmereUIOptions`, etc.) installed specifically on `_classic_beta_`, this project's actual
target client (unlike ElvUI, which isn't installed there at all). It's purpose-built for this
"WoW Forever" project and its code is explicitly engineered around this client's secret-value
system — genuinely the right reference, not ElvUI.

**The key technique**, found in `EllesmereUI\EllesmereUI_UICore.lua` (`PaintThreatPct`,
~line 1015) and `EllesmereUINameplates\EllesmereUINameplates.lua` (`NP_UpdateThreatPct`,
~line 3844):

```lua
-- NP_UpdateThreatPct:
local isTanking, status, pct = UnitDetailedThreatSituation("player", unit)
if type(pct) == "number" then
    EllesmereUI.PaintThreatPct(plate.threatPctText, pct, status, isTanking, ...)
end

-- PaintThreatPct:
function EllesmereUI.PaintThreatPct(fs, pct, status, isTanking, colorByThreat)
    fs:SetFormattedText("%.0f%%", pct)         -- see below
    if type(status) == "number" and not issecretvalue(status) then
        fs:SetTextColor(GetThreatStatusColor(status))
    elseif type(isTanking) == "boolean" then
        fs:SetTextColor(fold(isTanking, aggR, lowR), fold(isTanking, aggG, lowG), fold(isTanking, aggB, lowB))
        -- fold = C_CurveUtil.EvaluateColorValueFromBoolean
    end
end
```

Source comment above `NP_UpdateThreatPct`, verbatim: *"Percent and status are secret for
nameplate units: the percent goes straight to PaintThreatPct, never compared or stored."* —
i.e. the author already knows `pct` (`scaledPercentage`, the 3rd return of
`UnitDetailedThreatSituation`) comes back **secret** for nameplate units on this client, same
conclusion ThreatMeterNP reached independently for `rawThreat`/`rawPercentage`. The difference is
what they do about it:

1. **`fs:SetFormattedText("%.0f%%", pct)` — a widget *method* call, not Lua's own
   `string.format`.** This is the actual unlock. A secret number can't be read, compared, or
   passed through `string.format()` by addon Lua (that throws, same family of error as the
   `>` comparison and `if secretBool then` cases already in infos.md) — but handing it directly
   to a FontString's own `:SetFormattedText`/`:SetText` is a sanctioned "sink": the C-side
   widget formats and renders the value without ever exposing it back to Lua. The addon never
   learns the number; the *player* still sees it on screen, which is the whole point of the
   secret-value system (hide data from addon logic, not from the human). **This means
   ThreatMeterNP can show a real, exact percentage on this client after all — just never through
   `string.format`/`IsUsableNumber`/any Lua-side read of the value, only straight into a widget
   setter.**
2. **For color, when `status` is also secret**: `C_CurveUtil.EvaluateColorValueFromBoolean(secretBool, valueIfTrue, valueIfFalse)` — a Blizzard-provided "secret-safe select." It picks
   between two already-known *plain* values based on a possibly-secret boolean, entirely
   C-side; Lua never reads the boolean. Confirmed via two independent EllesmereUI call sites
   (`EllesmereUI_Kick.lua` for an ability-ready tint, `EllesmereUI_UICore.lua` for this threat
   color). This is the general pattern for "I need to branch display on a secret condition
   without ever reading it."
3. `GetThreatStatusColor(status)` — a **Blizzard global function** (not defined in EllesmereUI
   or found in the local Lua source dump — it's a built-in, used directly by Blizzard's own
   `UnitFrame.lua` too), maps a threat status number to its standard r,g,b. Reused as-is rather
   than reinventing a color table.

**Implemented in ThreatMeterNP** (`ApplyExactThreatPercentage` in ThreatMeterNP.lua, replacing the
`GetExactThreatPercentage` attempt from the `threatShowNumeric` investigation above): mutates
the widget directly rather than returning a value, specifically so the secret `pct` never has
to pass through a Lua-side read/format anywhere in ThreatMeterNP's own code. Deployed; not yet
live-confirmed by the user as of this writing, but — unlike the two earlier attempts — this one
is validated by a real, proven-working local addon on the exact same client, not just
documentation inference.

### Correction: secret-value comparison IS possible — just not unconditionally

Earlier entries in this file (and ThreatMeterNP's original raw-gap attempt) concluded raw threat
comparison/ranking was flatly blocked on this client. **That conclusion was wrong**, caught by
reading `EllesmereUIForeverEssentials_ThreatData.lua`'s real threat-list collector (the one
behind EllesmereUI's Damage-Meters "Threat" window and its minimap/raid-frame threat lists).

The actual rule: a **secret** value throws on comparison/arithmetic (confirmed, still true). A
**non-secret** value compares completely normally — `table.sort` with `a.raw > b.raw` just
works. The original ThreatMeterNP crash (`infos.md`, "secret values" section) was a **bug**
(missing an `issecretvalue()` guard before the first comparison), not evidence that raw threat
is *always* secret on this client. It was secret in the specific context tested (solo, open
world, low-level mob) — but secrecy here is evidently conditional, not blanket.

EllesmereUI's collector (`ns.NewCollector` → `Add`/`Collect`/`Sort` in
`EllesmereUIForeverEssentials_ThreatData.lua`) proves the general pattern for anything that
needs to **rank** multiple units by a secret-prone value:

```lua
local function Readable(v) return not issecretvalue(v) and v ~= nil end

local function Add(unit, mob, isPet)
    local tanking, _, scaled, rawPct, raw = UnitDetailedThreatSituation(unit, mob)
    if not (Readable(raw) and Readable(scaled) and Readable(tanking)) or raw <= 0 then return end
    -- only reaches here if raw/scaled/tanking are ALL non-secret right now
    list[#list + 1] = { unit = unit, raw = raw, scaled = scaled, tanking = tanking }
end

function c.Sort()
    table.sort(list, function(a, b) return a.raw > b.raw end) -- plain comparison, safe here
end
```

Read each candidate unit's value, **guard with `issecretvalue()`, and silently skip (don't
include in the list) any unit whose value is secret at that moment** — then sort/compare freely
among whatever's left. This gracefully degrades (fewer rows, or none, when secrecy applies more
broadly) rather than crashing or guessing. **Implemented in ThreatMeterNP** as
`CollectThreatEntries`/`ApplyThreatList` in ThreatMeterNP.lua, directly modeled on this file.

Practical implication for future work on this addon: don't assume a value is unconditionally
secret just because it was secret once in testing — the right pattern is always "attempt
read → `issecretvalue()` guard → skip/fallback," never "assume secret and avoid the attempt."

### ElvUI's threat meter — confirms the fallback approach, not a new capability

`ElvUI\Game\Shared\Modules\Nameplates\Elements\Threat.lua` doesn't fetch threat data itself —
ElvUI's unitframes are oUF-based, and the actual call lives in
`ElvUI_Libraries\Game\Shared\oUF\elements\threatindicator.lua` →
`oUF:GetThreatSituation(unit, feedbackUnit)` (in `oUF\init.lua`), which is just
`UnitThreatSituation(unit[, mobGUID])` — **the exact same single function** ThreatMeterNP's
Low/Medium/High fallback already uses. ElvUI's "working threat meter" is coarse
status-color-coded, not a numeric percentage; it corroborates that `UnitThreatSituation` is the
reliable, addon-safe building block here, it doesn't add a new technique beyond what we'd
already found.
- Note: ElvUI is not installed on `_classic_beta_` (the WoW Forever Beta target client) — it
  was examined from a copy in `_classic_`/`_classic_era_`/`_anniversary_`/`_retail_` instead,
  same source either way since it's not client-specific code.

### Geometry queries on a widget that just received secret-tainted text also throw

Discovered while fixing a background-sizing bug (ThreatMeterNP v0.9.8, reverted in v1.0.1): a
FontString's own `:GetStringWidth()` — called on `widgets.listRows[i]` right after
`:SetFormattedText(...)` rendered that row's threat value via the widget-sink technique (see
"the actual breakthrough" above) — appears to throw the same family of error as reading a
secret Lua value directly, even though `GetStringWidth()` never touches the secret value
itself; it only asks the widget for its own rendered pixel width. Not independently confirmed
against a Blizzard error message (the symptom observed was each subsequent list row silently
failing to render — consistent with an uncaught Lua error aborting the render loop immediately
after the first row, which already renders before the width query runs), but strong enough
circumstantial evidence to treat as true going forward: a `GetWidth()`/`GetHeight()`/
`GetLeft()`/`GetRight()`-style geometry read off a widget, taken after handing it secret-prone
text, is not safe to assume works just because the *value itself* was never read in Lua.
Plausible rationale: this closes off exactly the kind of side-channel the whole secret-value
system exists to prevent (inferring a secret number's digit count from its on-screen width).

**Practical implication**: once a widget has displayed a value through the sink technique,
treat it as fully opaque from then on — don't query its rendered geometry back, even for
unrelated purposes like background sizing. If a background/layout needs to span rendered text
whose content may include a secret value, size it off something else that's known not to
depend on the secret portion (e.g. a fixed reference row, like ThreatMeterNP's player list
background now using row 1's bounds unconditionally rather than measuring each row).

## Open questions / not yet scanned
- Exact structure of `plate.unitFrame` when Plater is active vs. default Blizzard nameplates
  vs. ElvUI nameplates (requirements.md says "add info to existing nameplates (Blizzard,
  Plater or ElvUI)" — need to check whether ElvUI nameplates expose `C_NamePlate.GetNamePlateForUnit`
  the same way, or need a different attach path). Not yet scanned — check ElvUI's nameplate
  module if/when we scope ElvUI support.
- Whether `UNIT_THREAT_LIST_UPDATE` / `UNIT_THREAT_SITUATION_UPDATE` events still exist on this
  client build (search hit files but didn't confirm exact event names fire — verify in-game or
  via `Blizzard_NamePlates.lua` event registration before relying on them; `UNIT_HEALTH`-style
  polling on nameplate update is a safe fallback PlaterTOT itself uses).
- Plater's internal script/mod system details (hook types, sandbox globals) — intentionally not
  deep-scanned since we decided against that route; revisit only if the standalone-addon
  approach turns out to be blocked for some reason.
