-- GuildHawk: Core logic (data, message picker, timers, slash commands)
local ADDON = ...
GuildHawk = GuildHawk or {}
local GH = GuildHawk

BINDING_HEADER_GUILDHAWK = "GuildHawk"
BINDING_NAME_GUILDHAWK_SEND = "Send next due recruitment post"

local MAX_LEN = 255
local MIN_INTERVAL = 60

local defaults = {
  messages = {},
  recent = {},
  sequential = false,
  running = false,
  seqIndex = 0,
  minimapAngle = 200,
  targets = {
    { kind = "CHANNEL", channel = "Trade", interval = 180, enabled = true, lastSent = 0 },
  },
}

local function copy(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = copy(v) end
  return r
end

function GH.InitDB()
  GuildHawkDB = GuildHawkDB or {}
  for k, v in pairs(defaults) do
    if GuildHawkDB[k] == nil then GuildHawkDB[k] = copy(v) end
  end
  GH.db = GuildHawkDB
end

function GH.Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffffd100GuildHawk:|r " .. tostring(msg))
end

---------------------------------------------------------------------------
-- Message pool
---------------------------------------------------------------------------
-- Split pasted text into messages: one per line, trimmed, blanks dropped.
-- Returns list, tooLongCount (lines over 255 are truncated to 255).
function GH.ParseMessages(text)
  local list, long = {}, 0
  for raw in (text or ""):gmatch("[^\r\n]+") do
    local line = raw:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then
      if #line > MAX_LEN then
        long = long + 1
        line = line:sub(1, MAX_LEN)
      end
      list[#list + 1] = line
    end
  end
  return list, long
end

function GH.ImportMessages(text, append)
  local list, long = GH.ParseMessages(text)
  if not append then GH.db.messages = {} end
  for _, m in ipairs(list) do GH.db.messages[#GH.db.messages + 1] = m end
  GH.db.recent = {}
  GH.db.seqIndex = 0
  return #list, long
end

local function isRecent(idx)
  for _, r in ipairs(GH.db.recent) do if r == idx then return true end end
  return false
end

-- Pick a message: random avoiding the last N used, or sequential.
function GH.PickMessage()
  local msgs = GH.db.messages
  local n = #msgs
  if n == 0 then return nil end

  local idx
  if GH.db.sequential then
    GH.db.seqIndex = (GH.db.seqIndex % n) + 1
    idx = GH.db.seqIndex
  else
    local window = math.min(20, math.floor(n / 2))
    GH.db.recent = GH.db.recent or {}
    local tries = 0
    repeat
      idx = math.random(n)
      tries = tries + 1
    until not isRecent(idx) or tries > 50
    table.insert(GH.db.recent, idx)
    while #GH.db.recent > window do table.remove(GH.db.recent, 1) end
  end
  return msgs[idx], idx
end

---------------------------------------------------------------------------
-- Targets / timers
---------------------------------------------------------------------------
function GH.ClampInterval(v)
  v = tonumber(v) or 180
  if v < MIN_INTERVAL then v = MIN_INTERVAL end
  return v
end

function GH.IsDue(t, now)
  return t.enabled and (now - (t.lastSent or 0)) >= t.interval
end

-- Most overdue enabled target, or nil.
function GH.NextDue()
  local now = GetTime()
  local best, bestOver
  for _, t in ipairs(GH.db.targets) do
    if GH.IsDue(t, now) then
      local over = now - (t.lastSent or 0) - t.interval
      if not bestOver or over > bestOver then best, bestOver = t, over end
    end
  end
  return best
end

function GH.TargetLabel(t)
  if t.kind == "CHANNEL" then return t.channel end
  return t.kind:sub(1, 1) .. t.kind:sub(2):lower()
end

---------------------------------------------------------------------------
-- Preview prompt flow
--   Prompt  : a target is due -> pick a message and show the preview
--   Next    : pick another random message (also marked as used)
--   Okay    : send it (runs from a click, so the protected send is allowed)
--   Skip    : drop this post and restart that channel's timer
--   Cancel  : stop the timer for this channel
--   CancelAll: stop every channel's timer
---------------------------------------------------------------------------
GH.pending = nil

local function channelId(t)
  if t.kind ~= "CHANNEL" then return nil, true end
  local id = GetChannelName(t.channel)
  if not id or id == 0 then return nil, false end
  return id, true
end

local function clearPending()
  GH.pending = nil
  if GH.HidePrompt then GH.HidePrompt() end
  if GH.UpdateUI then GH.UpdateUI() end
end

function GH.Prompt()
  if GH.pending then if GH.ShowPrompt then GH.ShowPrompt() end return end
  if not GH.db.running then return end
  if UnitIsDeadOrGhost("player") or InCombatLockdown() then return end
  local t = GH.NextDue()
  if not t then return end
  if #GH.db.messages == 0 then return end
  local _, ok = channelId(t)
  if not ok then
    GH.Print("You are not in channel '" .. tostring(t.channel) .. "'. Skipping it for this cycle.")
    t.lastSent = GetTime()
    return
  end
  GH.pending = { target = t, msg = GH.PickMessage() }
  if GH.ShowPrompt then GH.ShowPrompt() end
  if GH.UpdateUI then GH.UpdateUI() end
end

function GH.Next()
  if not GH.pending then return end
  GH.pending.msg = GH.PickMessage()
  if GH.ShowPrompt then GH.ShowPrompt() end
end

function GH.Approve()
  local p = GH.pending
  if not p then return end
  local t = p.target
  local id, ok = channelId(t)
  if not ok then
    GH.Print("You are not in channel '" .. tostring(t.channel) .. "'. Post dropped.")
  else
    SendChatMessage(p.msg, t.kind, nil, id)
  end
  t.lastSent = GetTime()
  clearPending()
end

function GH.Skip()
  local p = GH.pending
  if not p then return end
  p.target.lastSent = GetTime()
  clearPending()
end

function GH.CancelTarget()
  local p = GH.pending
  if not p then return end
  p.target.enabled = false
  GH.Print("Stopped the timer for " .. GH.TargetLabel(p.target) .. ".")
  clearPending()
end

function GH.CancelAll()
  for _, t in ipairs(GH.db.targets) do t.enabled = false end
  GH.db.running = false
  GH.Print("All timers stopped.")
  clearPending()
end

-- Keybind / /gh send: confirm the open preview, or open one if something is due.
function GH.SendNext()
  if GH.pending then GH.Approve() else GH.Prompt() end
end
function GuildHawk_SendNext() GH.SendNext() end

---------------------------------------------------------------------------
-- Events / slash
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, name)
  if name ~= ADDON then return end
  math.randomseed(time())
  GH.InitDB()
  -- lastSent uses GetTime(), which resets each session: make every target due after min wait.
  local now = GetTime()
  for _, t in ipairs(GH.db.targets) do t.lastSent = now - t.interval end
  if GH.BuildUI then GH.BuildUI() end
end)

SLASH_GUILDHAWK1 = "/gh"
SLASH_GUILDHAWK2 = "/guildhawk"
SlashCmdList["GUILDHAWK"] = function(arg)
  arg = (arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if arg == "start" then
    GH.db.running = true; GH.Print("Started.")
  elseif arg == "stop" then
    GH.db.running = false; GH.Print("Stopped.")
  elseif arg == "send" then
    GH.SendNext()
  elseif arg == "status" then
    GH.Print((GH.db.running and "Running" or "Stopped") .. ", " .. #GH.db.messages .. " messages.")
    local now = GetTime()
    for _, t in ipairs(GH.db.targets) do
      local left = math.max(0, t.interval - (now - (t.lastSent or 0)))
      GH.Print(string.format("  %s: %s, next in %ds", GH.TargetLabel(t), t.enabled and "on" or "off", left))
    end
  else
    if GH.ToggleConfig then GH.ToggleConfig() end
  end
  if GH.UpdateUI then GH.UpdateUI() end
end
