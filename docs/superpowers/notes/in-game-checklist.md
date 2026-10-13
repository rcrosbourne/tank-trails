# TankTrails in-game checklist (spec §9)

Install with `tools/install.sh "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns"`, then `/reload`.
Note anything odd with `/tt debug` and `/tt errors`.

## API checks (run these first; they decide the map plan's branches)

Inside any dungeon, out of combat:

1. Native dungeon maps?
   `/dump C_Map.GetMapInfo(291)` — a table named The Deadmines means native map entries exist.
   Then: `/run local n=0 for id=1,3000 do local m=C_Map.GetMapInfo(id) if m and m.mapType==Enum.UIMapType.Dungeon then n=n+1 print(id, m.name) end end print(n.." dungeon maps")`
   Record the count. Zero means the map plan uses `art.kind = "tiles"` with ids from the listfile.
2. Target names out of combat?
   Target a mob without pulling: `/dump issecretvalue(UnitName("target"))` — `false` means pulls get target names.
3. Room keys: walk the Deadmines and `/dump GetMinimapZoneText()` in each area. Expect "The Deadmines", "Mast Room", "Goblin Foundry", "Ironclad Cove". Write down any that differ.
4. Boss events: kill Rhahk'Zor, then `/tt debug`. Expect a `boss` line with his name (or `#id` if the name was secret).
5. Art by file id (only if check 1 found zero): find one id in the community listfile (https://wago.tools/files, search `interface/worldmap/deadmines`), then `/run local t=UIParent:CreateTexture() t:SetPoint("CENTER") t:SetSize(256,256) print(t:SetTexture(<fileDataID>))`. A tile appears mid-screen and the call returns true. `/reload` clears it.

## Feature checks

### Setup
1. Log in. Chat shows "TankTrails: Loaded." `/tt help` lists the commands. No Lua errors; `/tt errors` says "No errors."
2. Log out and back in inside a dungeon (not /reload): the HUD returns on the same room.
3. Import an export where a placed room has no `floor`: the import is rejected with a message and nothing changes.
4. `/tt hud` hides and shows the HUD. Drag it; `/tt lock`; dragging no longer moves it. `/tt scale 1.3` grows it.

### Learning mode (a dungeon with no route)
1. Enter the dungeon. The HUD appears with the dungeon name, "learning", a clock, and the current room.
2. Walk into a new area. Line 2 changes within a second. `/tt debug` shows the room events.
3. Target a mob, pull it. After combat, `/tt debug` shows a pull line. Die on purpose if cheap; the pull's deaths count goes up (visible in the export later).
4. `/tt note pull these back` — chat confirms the note for the current room.
5. Kill the first boss. Line 3's boss count goes up.
6. `/reload` mid-run. The HUD comes back on the same room with the same counts.
7. Leave the dungeon. The HUD hides and chat says "Re-enter within 30 minutes to continue the run, or /tt promote it now." `/tt promote` works from outside — chat confirms the route and step count.
8. `/tt export` opens a window with the dungeon text; it includes your note on that room's step. Copy it somewhere.

### Route mode
1. Re-enter the same dungeon. The HUD shows the route name, "Bosses 0/N", line 3 "Next: ..." and your note on line 4.
2. Walk the route. The next step advances on room changes and boss kills. Skip a room; the next boss kill re-anchors.
3. Walk somewhere not on the route. Line 2 shows "? <room>". Walk back; it clears.
4. `/tt note changed my mind` — line 4 updates at once. `/tt boss` ticks the next boss by hand (use it on a rare).
5. `/tt route <name>` with a wrong name lists the routes; with the right name switches.
6. `/tt import`, paste the exported text with one note edited, press Import, confirm. Line 4 shows the edited note.
7. `/tt reset`, confirm. The HUD drops back to learning mode. `/tt import` the saved text to restore.

### Arrow (needs two placed rooms; until the map plan lands, place by import)
1. In the exported text, give two consecutive route rooms positions, e.g. `floor = 1, x = 0.5, y = 0.8` and `floor = 1, x = 0.5, y = 0.2`, import it, stand in the first room. The arrow points up. If it points down, set `Theme.ARROW_ROTATION_SIGN = -1`.
