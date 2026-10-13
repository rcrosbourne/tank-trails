local M = {}

-- A scriptable stand-in for the game globals the adapters read.
-- state: secrets (set of values that are secret), zoneText, instance = { kind, name, id } or nil,
--        target = { isPlayer, name } or nil, now (seconds), chat (messages printed), ticker (fn), popup.
function M.new(state)
  state = state or {}
  state.secrets = state.secrets or {}
  state.chat = state.chat or {}
  local env = {}
  env.issecretvalue = function(v) return v ~= nil and state.secrets[v] == true end
  env.GetMinimapZoneText = function() return state.zoneText end
  env.IsInInstance = function()
    if not state.instance then return false, "none" end
    return true, state.instance.kind or "party"
  end
  env.GetInstanceInfo = function()
    local i = state.instance
    if not i then return nil end
    return i.name, i.kind or "party", 1, "Normal", 5, 0, false, i.id
  end
  env.UnitExists = function() return state.target ~= nil end
  env.UnitIsPlayer = function() return state.target ~= nil and state.target.isPlayer == true end
  env.UnitName = function() return state.target and state.target.name end
  env.CreateFrame = function() return M.frame() end
  env.C_Timer = { NewTicker = function(_, fn)
    state.ticker = fn
    return { Cancel = function() state.ticker = nil end }
  end }
  env.time = function() return state.now or 0 end
  env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) table.insert(state.chat, msg) end }
  env.StaticPopupDialogs = {}
  env.SlashCmdList = {}
  env.StaticPopup_Show = function(which, text1, text2, data)
    state.popup = { which = which, data = data }
    return {}
  end
  return env, state
end

function M.frame()
  local f = { events = {}, scripts = {}, shown = true }
  function f:RegisterEvent(e) self.events[e] = true end
  function f:UnregisterAllEvents() self.events = {} end
  function f:SetScript(k, fn) self.scripts[k] = fn end
  function f:fire(event, ...)
    if self.scripts.OnEvent then self.scripts.OnEvent(self, event, ...) end
  end
  return f
end

return M
