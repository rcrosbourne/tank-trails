# TankTrails — Design Spec

**Date:** 2026-10-12
**Status:** Draft for review
**Repository:** `~/lua_projects/dungeon_map`
**Conventions:** follows YardTrails (`../my-quest-addon-v2`): Interface 16001, a Model / Wow / UI / Core split, busted through a hererocks Lua 5.1, docs under `docs/superpowers/`.

## 1. Purpose

While the player tanks a World of Warcraft: Forever dungeon, TankTrails shows which room they are in, which room or boss comes next and which way it lies, and a note for the pull in front of them. It learns each dungeon from the player's own runs, so the second run is guided even where nothing shipped.

Forever runs on the Mainline (12.x) code family with Midnight's addon restrictions active. Inside an instance, addons get no position and no facing (the patch 7.1 rule, still in force), and Blizzard is leaning against adding dungeon maps as a design choice. TankTrails therefore works from the two things an instance still reports: the minimap zone text and encounter events.

YardTrails keeps the quest side of dungeons (offers, pickup tours, the boss checklist with quests). TankTrails owns navigation and tank notes. The two do not depend on each other.

### Success criteria

1. In a dungeon with a route, the HUD shows the current room within a second of each sub-zone change, the next step, and the current step's note.
2. In a dungeon with no route, the run is recorded, and `/tt promote` turns it into a route that guides the next run with no hand editing.
3. Placing a room is one click. Afterwards the map shows the room on the art, and the HUD arrow points from the current room to the next placed step.
4. Exporting a dungeon and importing the text reproduces it exactly. The export is a valid shipped data file.
5. `/reload` or a disconnect mid-run returns to the same cursor with the run log intact.
6. Every rule in §6 (detection engine) runs under busted outside the game.

## 2. Decisions

| Decision | Choice |
|---|---|
| Product shape | A route-step engine with two views, HUD and map, over one "where am I in the route" state |
| Dungeon identity | `instanceMapID` from `GetInstanceInfo`, stable across locales and builds |
| Room identity | The minimap zone text, exactly as the client shows it. The instance's own name is a room for areas with no sub-zone |
| Route anchors | Only events the game still reports inside instances: room entered, boss died |
| Localization accuracy | As coarse as the sub-zones. Where they are sparse, boss kills carry the route |
| Data entry | Automatic recording; one click per room to place it on the map; notes typed after the run or shipped |
| Map art | Per dungeon, in priority order: native map entries via `C_Map`; the client's own art files by file id; an image file from any installed addon (DFL Dungeon Journal, Forever Dungeon Routes), personal use only; a blank canvas |
| Data | Shipped Lua files plus SavedVariables. Saved wins per room, per boss and per route. The export format is the shipped file format |
| Scope of shipped data | The early (13-29) and mid (25-45) dungeons |
| Dependencies | None. No Ace, no LibStub, no HereBeDragons |
| Instances | Party dungeons only in v1 |
| Build order | Recorder, storage, HUD, promote and export first, so runs during the beta (ends 2026-10-21) produce data; the map second; starter data third |

## 3. What an instance still reports

Verified during the 2026-10-12 spike (sources in §14). "Secret" means the value exists but tainted code cannot read or compare it.

| Call or event | Inside a Forever dungeon |
|---|---|
| `C_Map.GetPlayerMapPosition`, `UnitPosition`, `GetPlayerFacing` | nil |
| `GetMinimapZoneText`, `GetSubZoneText`, `ZONE_CHANGED*` events | work |
| `GetInstanceInfo`, `IsInInstance` | work |
| `ENCOUNTER_END`, `BOSS_KILL` | fire; payload fields guarded as possibly secret |
| `PLAYER_REGEN_DISABLED/ENABLED`, `PLAYER_DEAD`, `PLAYER_TARGET_CHANGED` | work |
| `UnitName` on a non-player unit | secret in combat; out of combat to be verified (§9 check 2) |
| Creature ids, combat log, `MINIMAP_PING` | secret or unavailable |
| Addon chat (`SendAddonMessage`) | blocked during boss encounters |
| `MinimapCompassTexture:GetRotation()` | reported to leak facing in Midnight raids; not used in v1 |
| Dungeon map art | the old dungeons' art files are in the client; native `UiMap` entries unconfirmed (§9 check 1) |

## 4. Architecture

Four layers. Game calls live only in Wow and UI; Model takes plain tables and returns plain tables.

| Unit | Does | Used by | Depends on |
|---|---|---|---|
| `Model/Route` | Cursor rules (§6.5): fold a route and a list of events into `{cursor, done, offRoute, unexpected}`; compute next step and progress | App, Hud, MapWindow | nothing |
| `Model/Recorder` | Turns adapter records into run-log events: rooms, pulls with target and deaths, bosses with de-duplication | App | nothing |
| `Model/Promote` | Run log to route steps: flap collapse, duplicate merge, boss interleave, note carry-over, boss room and id learning | Commands | nothing |
| `Model/Merge` | Shipped plus saved overlay into the effective dungeon; creates unknown dungeons | App, Store | nothing |
| `Model/Serialize` | Deterministic export text; import via `loadstring` in an empty environment; validation | Commands, RoutePanel | nothing |
| `Model/Geometry` | Bearing between placed points, tile grid layout, aspect-fit rectangle | Hud, Canvas | nothing |
| `Wow/Safe` | Strips secret values; nil for anything `issecretvalue` flags | every adapter | game |
| `Wow/InstanceWatch` | Current party dungeon id and name from `env` | App | Safe |
| `Wow/Events` | Registers game events, reads zone text, encounter and combat payloads, the out-of-combat target; emits records | App | Safe |
| `Wow/MapArt` | Resolves a floor's art spec to textures: native via `C_Map`, tiles by file id, image by path, or none; reports why a kind was skipped | Canvas | Safe |
| `Wow/Store` | SavedVariables access, run-log persistence, recent-run cap | App, Commands | game |
| `UI/Theme` | Colours, fonts, frame backdrop helpers | all UI | game |
| `UI/Hud` | The four-line HUD | App | Route, Geometry, Theme |
| `UI/MapWindow` | Window chrome: title bar, floor buttons, route cycle, prompt bar; owns Canvas and RoutePanel | App | Canvas, RoutePanel, Theme |
| `UI/Canvas` | Art layer, room and boss markers, route line, placement clicks | MapWindow | MapArt, Geometry, Line |
| `UI/RoutePanel` | Step list with notes editing, unplaced rooms, place buttons, Promote / Export / Import | MapWindow | Serialize, Theme |
| `UI/Line` | Rotated texture strips between two canvas points | Canvas | game |
| `Core/App` | Wiring: run lifecycle, event dispatch, replay on change, view refresh | Init | everything |
| `Core/Commands` | `/tt` handlers | Init | App, Promote, Serialize, Store |
| `Core/Util` | Error trap, timers, string helpers | all | game |

## 5. Data model

One schema serves shipped files, SavedVariables and the export text.

### 5.1 Dungeon record

A shipped file under `TankTrails/Data/Dungeons/` is exactly what `/tt export` prints:

```lua
TankTrails_RegisterDungeon({
  id   = 36,                      -- instanceMapID from GetInstanceInfo
  name = "The Deadmines",
  art  = { kind = "native",       -- "native" | "tiles" | "image" | "none"
           floors = { { name = "Mines", uiMapID = 291 },
                      { name = "Ironclad Cove", uiMapID = 292 } } },
  rooms = {                       -- key = minimap zone text, exactly as shown
    ["The Deadmines"]  = { floor = 1, x = 0.12, y = 0.80 },
    ["Mast Room"]      = { floor = 1, x = 0.40, y = 0.60 },
    ["Goblin Foundry"] = {},                              -- seen, not yet placed
    ["Ironclad Cove"]  = { floor = 2, x = 0.50, y = 0.50 },
  },
  bosses = {                      -- key = boss name
    ["Rhahk'Zor"] = { encounterID = nil, room = "The Deadmines" },
    ["Mr. Smite"] = { room = "Ironclad Cove", floor = 2, x = 0.45, y = 0.62 },
  },
  routes = {
    { name = "Standard", steps = {
        { room = "The Deadmines", note = "Pull the first two packs back to the tunnel" },
        { boss = "Rhahk'Zor" },
        { room = "Mast Room",     note = "Patrol on the ramp, wait at the door" },
        { boss = "Sneed" },
    } },
  },
})
```

Field rules:

- `art.floors[i]` by kind. `native`: `{ name, uiMapID }`. `tiles`: `{ name, fileDataIDs = {...}, cols, rows }`, each tile 256 by 256. `image`: `{ name, image = "Interface\\AddOns\\<folder>\\<file>", width, height }`. `none`: `{ name }`; if `floors` is absent, one floor named "Map".
- Positions `x`, `y` run 0 to 1 across the floor image, origin top left, as on Blizzard's maps. They are stored to four decimals.
- A room record exists once the room has been seen (`seenAt` is set then) and is placed once `floor`, `x` and `y` are set.
- A boss without its own `floor`, `x`, `y` is drawn at its room's position. `encounterID` is learned at the first kill that reports one.
- A step has exactly one of `room` or `boss`, and an optional `note`.

### 5.2 Run log

Per character, in `TankTrailsCharDB.run`, written on every event:

```lua
run = { dungeon = 36, name = "The Deadmines", startedAt = 1791850000, endedAt = nil,
  routeName = "Standard",
  events = {
    { t = 12.4, kind = "room", room = "The Deadmines" },
    { t = 30.1, kind = "pull", room = "The Deadmines", target = "Defias Miner", duration = 8.2, deaths = 0 },
    { t = 95.0, kind = "boss", name = "Rhahk'Zor", encounterID = 1234, room = "The Deadmines" },
    { t = 400.2, kind = "boss", name = "Cookie", manual = true, room = "Ironclad Cove" },
} }
```

`t` is seconds since `startedAt`. `target` is present only when the pre-pull target name was readable. `manual` marks a `/tt boss` tick, whose `name` comes from the route step it ticked.

### 5.3 Account data

```lua
TankTrailsDB = {
  dungeons = { [36] = { --[[ same fields as a shipped file, any subset ]] activeRoute = "Standard" } },
  runs     = { [36] = { run1, run2 } },   -- newest first, at most 5
  settings = { hud = { point, x, y, scale, locked }, map = { point, x, y, width, height }, autoOpen = true },
}
```

### 5.4 Merge

The effective dungeon starts as a deep copy of the shipped record, or `{ id, name }` when nothing shipped. The saved overlay is applied on top: `name` and `art` replace when set; each saved room, boss and route replaces the shipped one with the same key or name as a whole; shipped routes with no saved counterpart stay; `activeRoute` comes from saved.

### 5.5 Export and import

Export writes the effective dungeon as the §5.1 text with sorted keys, two-space indent and `%q`-escaped strings, into a copyable edit box. Import runs the pasted text with `loadstring` under an environment that defines only `TankTrails_RegisterDungeon`, inside `pcall`. It is rejected unless exactly one dungeon is registered, `id` is a number, every step has exactly one of `room` or `boss`, and every position lies in 0 to 1. After a confirm, it replaces that dungeon's saved overlay.

### 5.6 Known limits

Room keys are the client's localized text, so shipped data serves English clients only. Ragefire Chasm and the Stockade have no sub-zones: their routes are boss steps only, with the instance name as the single room.

## 6. Detection engine

### 6.1 Run lifecycle

On `PLAYER_ENTERING_WORLD` and `ZONE_CHANGED_NEW_AREA`, if `IsInInstance` reports "party", `GetInstanceInfo` supplies the dungeon id and name. If `TankTrailsCharDB.run` has the same dungeon and no `endedAt`, it resumes; otherwise any stale run is ended and filed, and a new run starts. When the player is no longer in that instance, the run gets `endedAt`, is filed under `TankTrailsDB.runs[id]` (newest first, capped at five) and cleared from the character.

### 6.2 Rooms

Events `ZONE_CHANGED`, `ZONE_CHANGED_INDOORS`, `ZONE_CHANGED_NEW_AREA`, plus a one-second ticker that re-reads the text as a safety net. The room is `GetMinimapZoneText`; empty text is ignored; a room event is emitted only when the text differs from the last emitted room. A room seen for the first time gets a record with `seenAt`.

### 6.3 Bosses

`ENCOUNTER_END` with success, and `BOSS_KILL`. Every payload field passes through `Wow/Safe`; a secret field becomes nil. Boss identity for de-duplication and matching is the encounter id when both sides have one, else the name. Two boss events with the same identity within five seconds are one kill. `/tt boss` emits a manual boss event carrying the name of the next undone boss step.

### 6.4 Pulls

`PLAYER_REGEN_DISABLED` opens a pull with the current room and time; `PLAYER_REGEN_ENABLED` closes it with `duration`; `PLAYER_DEAD` while a pull is open increments its `deaths`. Out of combat, `PLAYER_TARGET_CHANGED` remembers the target's name and the time when the unit exists, is not a player, and the name is not secret. A pull that opens within ten seconds of that memory takes the name as `target`. If names prove secret out of combat, pulls simply carry no target.

### 6.5 Cursor

A route is steps 1 to n. State is `{ cursor, done, offRoute, unexpected }`, with `cursor` starting at 0 and `done` a set of step indices. The state is never stored; it is the fold of the run's events over the active route, recomputed whenever the route, the run or the active route changes.

- **Room R:** the first step after the cursor whose room is R becomes the cursor and clears `offRoute`. If there is none, the nearest step at or before the cursor whose room is R becomes the cursor (backtracking). If there is none at all, the cursor stays and `offRoute` is R.
- **Boss B:** the first boss step after the cursor matching B is marked done and becomes the cursor. If there is none, the first matching boss step anywhere is marked done and becomes the cursor. If B matches no step, it is appended to `unexpected`.
- **Pull events** do not move the cursor.
- **Next** is the first step after the cursor that is not a done boss; nil means the route is complete.
- **Progress** is the number of done boss steps over the number of boss steps.

### 6.6 Route selection

The run uses the dungeon's `activeRoute`, else its first route. When the run's first room event matches no step in that route but matches a step in another route of the same dungeon, the run switches to the first such route for this run only. This is how the Scarlet Monastery wings and route variants select themselves.

### 6.7 Learning mode

A dungeon with no routes. The recorder runs unchanged; there is no cursor. The HUD shows the current room, rooms seen and bosses killed, and tells the player to `/tt promote` when the run ends.

### 6.8 Promotion

Input: a run log. Output: a route.

1. Take the room events in order with their stay lengths (next event time minus this one; the last stay ends at `endedAt` or now).
2. Collapse flaps until nothing changes: where rooms `A, B, A` appear and the stay in `B` is under fifteen seconds, drop `B` and merge the two `A` stays. Then merge consecutive duplicates.
3. Interleave boss events, including manual ticks, by time: a boss falls after the room step whose stay contains its time.
4. Steps are the result in order, rooms as room steps, bosses as boss steps.
5. If a route with the target name exists, carry notes over: for each new step, the first unused step of the old route with the same kind and key donates its note.
6. For each boss event, set `bosses[name].room` to the kill room and `encounterID` when known.

`/tt promote [name]` names the route "Recorded YYYY-MM-DD" by default, saves it, sets it active, and asks before overwriting a same-named route.

## 7. Views and commands

### 7.1 HUD

A frame the player drags into place once; `/tt lock` pins it. Position, scale and lock state persist. Four lines:

1. Small: dungeon, route name, "Bosses 2/6", run time.
2. Large: the current room. An off-route room shows a "?" prefix.
3. "Next: Mast Room" or "Next: Sneed", with an arrow glyph rotated to the bearing from the current room's position to the next step's when both are placed on the same floor. Different floors show "up to Ironclad Cove" or "down to Mines". Missing positions show no arrow.
4. The current step's note, at most two lines; if empty, the next step's note dimmed.

Bearing is computed in image space with y pointing down, so zero points up the screen. In learning mode line 3 reads "Learning: 4 rooms, 1 boss" and line 4 says to `/tt promote` when done. Clicking the HUD toggles the map.

### 7.2 Map window

Movable and resizable, with a minimum of 400 by 300. `/tt` toggles it; with `autoOpen` it opens on entering a dungeon. Title bar: dungeon name, one button per floor, a route cycle button. Canvas on the left, route panel on the right, prompt bar along the bottom. Geometry persists.

Canvas:

- **Art layer**, by `art.kind`. Native: `C_Map.GetMapArtLayers(uiMapID)` gives layer and tile sizes, `C_Map.GetMapArtLayerTextures(uiMapID, 1)` the tiles, laid out row by row with `cols = ceil(layerWidth / tileWidth)`. Tiles: the same grid from `fileDataIDs`, `cols`, `rows`. Image: one texture. None: a dark canvas with a faint grid. The image rectangle is aspect-fitted inside the canvas, and all positions are relative to that rectangle.
- **Rooms:** a dot and label per placed room on the shown floor; the current room pulses.
- **Bosses:** a skull at the boss's own position, else its room's; greyed once done.
- **Route line:** `UI/Line` strips between consecutive placed steps on the shown floor, in step order. A step on another floor breaks the line with a small "to <floor>" tag.

### 7.3 Placement

The canvas holds an armed target, `{ kind = "room" | "boss", key }`. Entering a room with no position arms that room and the prompt bar reads "Place Mast Room: click the map". The next click on the image rectangle writes `floor` (the shown floor), `x` and `y` to the saved overlay and clears the arm. Shift+click arms the current room even if already placed. Each step in the route panel has a place button that arms its room or boss. Markers do not drag in v1.

### 7.4 Route panel

The steps of the active route in order: icon, name, note. The current step is highlighted; done bosses are struck through. Clicking a note opens a multi-line edit box; Enter saves to the saved overlay and triggers a replay. Below the steps: the unplaced rooms, newest `seenAt` first, each with a place button. Buttons: Promote, Export, Import, Rename route.

### 7.5 Commands

```
/tt                 toggle the map
/tt hud             toggle the HUD        /tt lock           pin or unpin the HUD
/tt note <text>     note on the current step
/tt boss            tick the next boss by hand
/tt promote [name]  run log into a route  /tt route <name>   switch the active route
/tt export          copyable text         /tt import         paste box
/tt autoopen on|off /tt scale <n>
/tt debug           dungeon id, room text, cursor, last ten events, which calls came back nil or secret
/tt errors          errors caught since login
/tt reset           wipe this dungeon's saved overlay, after a confirm
```

Art is configured in data, not by command. `/tt debug` reports which art kind is in use and why a higher-priority one was skipped.

## 8. Error handling

- Every event handler and UI callback runs under `Util.trap`; failures are listed by `/tt errors` and never stop the recorder.
- `Wow/Safe` turns secret values into nil before they reach the Model. Empty zone text during loading screens is ignored.
- Art degrades per session: a native map id `C_Map` won't answer, a tile or image `SetTexture` can't load, each falls back to the blank canvas, and `/tt debug` records which call failed.
- The cursor is derived by replay, so editing a route mid-run, switching routes, or reloading never desyncs. The run log is written on every event, and a run resumes on login when the instance id matches.
- Raids and battlegrounds are ignored.
- If a future patch restricts zone text or encounter events, the HUD shows the affected field as unavailable and `/tt debug` names the call.

## 9. In-game verification

Kept in `docs/superpowers/notes/in-game-checklist.md`. Five checks gate plan branches and run before the code that depends on them:

1. `/dump C_Map.GetMapInfo(291)` and a scan of ids 1 to 3000 for `mapType == Enum.UIMapType.Dungeon`. Native art if dungeon maps exist; otherwise the `tiles` kind with ids from the community listfile.
2. `/dump issecretvalue(UnitName("target"))` on a mob, out of combat, inside a dungeon. Decides whether pulls carry target names.
3. `/dump GetMinimapZoneText()` through the Deadmines rooms. Confirms the room keys and that the zone events fire.
4. `ENCOUNTER_END` or `BOSS_KILL` on Rhahk'Zor, seen in `/tt debug`.
5. `SetTexture` with one file id from the listfile, and its return value.

Then the feature checklist: HUD states including learning mode and off-route; placement, re-placement and boss placement; the route line across a floor change; promote from a recorded run; export then import round trip; reload resume mid-run.

## 10. Testing

Toolchain as YardTrails: `python3 -m hererocks .lua -l 5.1 -r latest`, `.lua/bin/luarocks install busted`, `.lua/bin/busted`. `.busted` sets `lpath` to `TankTrails/?.lua;spec/?.lua`. Modules load both in game (`local _, ns = ...`) and under `require`.

`spec/helpers/fake_env.lua` is a scriptable `env`: zone text, instance info, `issecretvalue`, time, and a way to fire events into the adapters.

Specs:

- `route_spec`: forward match, backtrack, off-route, boss re-anchor forward and anywhere, unexpected boss, next skipping done bosses, route complete, progress, replay determinism (same events, same state).
- `recorder_spec`: room change only on difference, pull open and close with duration, deaths against the open pull, target captured within ten seconds and not after, boss de-duplication within five seconds, secret fields stripped, manual boss event.
- `promote_spec`: flap collapse under fifteen seconds and not over, consecutive duplicate merge, boss interleave by stay, note carry-over by kind and key in order, boss room and id learning, default route name.
- `merge_spec`: per-key and per-name overrides, shipped routes retained, unknown dungeon creation, `activeRoute`.
- `serialize_spec`: round trip of the §5.1 example, sorted keys, quotes and newlines in notes, rejection of zero or two registrations, of a step with both keys, and of a position outside 0 to 1.
- `geometry_spec`: bearing on the four axes and a diagonal, tile grid columns and rows, aspect fit for wide and tall canvases.
- `instance_watch_spec`: party only, id and name, resume versus new run.

UI is covered by the in-game checklist only.

## 11. Layout and tooling

```
dungeon_map/
  TankTrails/
    TankTrails.toc            ## Interface: 16001, SavedVariables: TankTrailsDB, SavedVariablesPerCharacter: TankTrailsCharDB
    Core/   Init.lua App.lua Util.lua Commands.lua
    Model/  Route.lua Recorder.lua Promote.lua Merge.lua Serialize.lua Geometry.lua
    Wow/    Safe.lua InstanceWatch.lua Events.lua MapArt.lua Store.lua
    UI/     Theme.lua Hud.lua MapWindow.lua Canvas.lua RoutePanel.lua Line.lua
    Data/   Dungeons.xml and Dungeons/<Name>.lua
  spec/   *_spec.lua and helpers/fake_env.lua
  tools/  install.sh and tiles_from_listfile.lua
  docs/superpowers/  specs plans notes
  .busted  .gitignore  README.md
```

`tools/install.sh` rsyncs `TankTrails/` into an AddOns folder, refusing any path that does not end in `AddOns`; the Forever client is `/Applications/World of Warcraft/_classic_beta_/Interface/AddOns`. `tools/tiles_from_listfile.lua` is an offline script that reads the community listfile and prints `fileDataIDs`, `cols` and `rows` for a dungeon's `interface/worldmap/<dungeon>/` tiles; it is used only if check 1 in §9 fails.

## 12. Starter data

For the early and mid dungeons: room keys from the wiki sub-zone lists, verified in game; routes in the standard clear order; positions placed with the click tool and exported; tank notes drafted from Classic tank guides and shortened to one line each. Each dungeon is one commit. This is a content track in the plan, separate from code, and it starts after the map exists.

Early: Hall of Thanes, Ragefire Chasm, Ruins of Lordaeron, The Deadmines, Wailing Caverns, Shadowfang Keep, Excavation Site: Wetlands, The Stockade, City of Dalaran. Mid: Blackfathom Deeps, Razorfen Kraul, Gnomeregan, Scarlet Monastery (four wings), Drowned City, Razorfen Downs. The new Forever dungeons ship with `art.kind = "none"` unless an image source is configured locally.

## 13. Out of scope for v1

A live position dot (dead reckoning from the compass texture), party sync, minimap-tile art for the new dungeons, hand-traced room polygons, draggable markers, patrol timers, threat or any combat data, raids, non-English clients, and a settings window.

## 14. Sources

- Forever overview: https://warcraft.wiki.gg/wiki/World_of_Warcraft:_Forever
- Interface numbers, Forever beta 16001: https://warcraft.wiki.gg/wiki/TOC_format
- Position and facing restricted in instances: https://warcraft.wiki.gg/wiki/API_C_Map.GetPlayerMapPosition, https://warcraft.wiki.gg/wiki/API_GetPlayerFacing, https://warcraft.wiki.gg/wiki/API_UnitPosition
- Secret values: https://warcraft.wiki.gg/wiki/Secret_Values, https://warcraft.wiki.gg/wiki/Patch_12.0.0/Planned_API_changes
- Blizzard on dungeon maps: https://www.wowhead.com/forever/news/dungeon-maps-likely-not-coming-to-wow-forever-383317
- Forever on the Mainline code family: https://wowforevergame.wiki/classic-plus/wow-forever-addons-guide/
- Existing addons: https://www.curseforge.com/wow/addons/forever-dungeon-routes, https://www.curseforge.com/wow/addons/hiddenmaps, https://www.curseforge.com/wow/addons/dfl-dungeon-journal
- Map API: https://warcraft.wiki.gg/wiki/API_C_Map.GetMapArtLayers, https://warcraft.wiki.gg/wiki/API_C_Map.GetMapArtLayerTextures
- Retail map ids for the old dungeons, to try in check 1: https://warcraft.wiki.gg/wiki/UiMapID
