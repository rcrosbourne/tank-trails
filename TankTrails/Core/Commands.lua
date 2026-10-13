local _, ns = ...
ns = ns or {}
local Util = ns.Util or require("Core.Util")

local Commands = {}
Commands.__index = Commands
ns.Commands = Commands

Commands.USAGE = {
  "/tt - toggle the map",
  "/tt hud - toggle the HUD;  /tt lock - pin or unpin it;  /tt scale <0.5-2>",
  "/tt note <text> - note on the current step;  /tt boss [name] - tick a boss by hand",
  "/tt promote [name] - turn the run into a route;  /tt route <name> - switch route",
  "/tt export;  /tt import;  /tt autoopen on|off;  /tt debug;  /tt errors;  /tt reset",
}

function Commands.parse(msg)
  msg = Util.trim(msg)
  local verb, rest = msg:match("^(%S+)%s*(.*)$")
  return (verb or ""):lower(), Util.trim(rest or "")
end

function Commands.create(app, env, ui)
  local self = setmetatable({ app = app, env = env, ui = ui }, Commands)
  local function trap(label, fn) return Util.wrap(app.errors, label, fn) end

  local function say(ok, msg)
    if msg then app:print(msg) end
    return ok
  end

  local function confirm(text, onYes)
    env.StaticPopupDialogs["TANKTRAILS_CONFIRM"] = env.StaticPopupDialogs["TANKTRAILS_CONFIRM"] or {
      text = "%s", button1 = "Yes", button2 = "No", timeout = 0, whileDead = true, hideOnEscape = true,
      preferredIndex = 3, OnAccept = function(_, data) data.onYes() end,
    }
    env.StaticPopup_Show("TANKTRAILS_CONFIRM", text, nil, { onYes = trap("confirm", onYes) })
  end

  local function usage()
    for _, line in ipairs(Commands.USAGE) do app:print(line) end
  end

  self.handlers = {
    [""] = function() app:toggleMap() end,
    hud = function() app:toggleHud() end,
    lock = function() app:print(app:lockHud() and "HUD locked." or "HUD unlocked.") end,
    note = function(rest) say(app:note(rest)) end,
    boss = function(rest) say(app:tickBoss(rest ~= "" and rest or nil)) end,
    promote = function(rest)
      local name = rest ~= "" and rest or nil
      local r, msg = app:promote(name)
      if r == "confirm" then
        confirm("A route with that name already exists. Replace it?", function() say(app:promote(name, true)) end)
      else
        say(r, msg)
      end
    end,
    route = function(rest) say(app:switchRoute(rest)) end,
    export = function()
      local text, msg = app:exportText()
      if text then ui.textBox():show("Export: copy this text (Ctrl+C)", text) else app:print(msg) end
    end,
    import = function()
      ui.textBox():show("Import: paste a dungeon file, then press Import", "", trap("import", function(text)
        local r, msg = app:importText(text)
        if r == "confirm" then
          confirm("Replace saved data for " .. tostring(msg) .. "?", function()
            say(app:importText(text, true))
            ui.textBox():hide()
          end)
        else
          say(r, msg)
        end
      end))
    end,
    autoopen = function(rest)
      app:setAutoOpen(rest == "on")
      app:print(rest == "on" and "The map will open when you enter a dungeon." or "The map stays closed until /tt.")
    end,
    scale = function(rest)
      local n = tonumber(rest)
      if n and n >= 0.5 and n <= 2 then app:setScale(n) else app:print("Scale must be between 0.5 and 2.") end
    end,
    debug = function()
      for _, line in ipairs(app:debugLines()) do app:print(line) end
    end,
    errors = function()
      local entries = app.errors.entries
      if #entries == 0 then app:print("No errors.") return end
      for _, e in ipairs(entries) do app:print(e.label .. ": " .. e.message) end
    end,
    reset = function()
      local r, msg = app:reset()
      if r == "confirm" then
        confirm("Wipe the saved rooms, routes and notes for this dungeon?", function() say(app:reset(true)) end)
      else
        say(r, msg)
      end
    end,
    help = usage,
  }

  function self:run(msg)
    trap("command", function()
      local verb, rest = Commands.parse(msg)
      local handler = self.handlers[verb]
      if handler then handler(rest) else usage() end
    end)()
  end

  if env.SlashCmdList then
    env.SLASH_TANKTRAILS1 = "/tt"
    env.SlashCmdList.TANKTRAILS = function(msg) self:run(msg) end
  end
  return self
end

return Commands
