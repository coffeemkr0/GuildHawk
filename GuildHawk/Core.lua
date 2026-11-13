-- GuildHawk: Core logic (data, message picker, timers, slash commands)
local ADDON = ...
GuildHawk = GuildHawk or {}
local GH = GuildHawk

BINDING_HEADER_GUILDHAWK = "Guild Hawk"
BINDING_NAME_GUILDHAWK_SEND = "Send next due recruitment post"

local MAX_LEN = 255
local MIN_INTERVAL = 60

local defaults = {
  messages = {},
  recent = {},
  sequential = false,
  running = false,
  seqIndex = 0,
  nextId = 0,
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
  DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Guild Hawk:|r " .. tostring(msg))
end

---------------------------------------------------------------------------
-- Message pool
--   Each message is { id, text, enabled, fav }. Position in the list is its priority:
--   higher rows are picked more often in random mode, and "In order" mode walks the list
--   top to bottom. Favorites get an extra boost. Disabled messages are never picked.
---------------------------------------------------------------------------
local FAV_WEIGHT = 3

local function clip(text)
  text = (text or ""):gsub("[\r\n]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  local long = #text > MAX_LEN
  if long then text = text:sub(1, MAX_LEN) end
  return text, long
end

local function newMessage(text)
  GH.db.nextId = (GH.db.nextId or 0) + 1
  return { id = GH.db.nextId, text = text, enabled = true, fav = false }
end

-- Upgrade messages saved by older versions (plain strings) to the table form.
function GH.MigrateMessages()
  local msgs, changed = GH.db.messages, false
  for i, v in ipairs(msgs) do
    if type(v) == "string" then msgs[i] = newMessage(v); changed = true end
  end
  if changed then GH.db.recent = {}; GH.db.seqIndex = 0 end
end

-- Split pasted text into messages: every line break starts a new message.
-- Returns list, tooLongCount (lines over 255 are truncated to 255).
function GH.ParseMessages(text)
  local list, long = {}, 0
  for raw in (text or ""):gmatch("[^\r\n]+") do
    local line, wasLong = clip(raw)
    if line ~= "" then
      if wasLong then long = long + 1 end
      list[#list + 1] = line
    end
  end
  return list, long
end

function GH.ImportMessages(text, append)
  local list, long = GH.ParseMessages(text)
  if not append then GH.db.messages = {} end
  for _, line in ipairs(list) do
    GH.db.messages[#GH.db.messages + 1] = newMessage(line)
  end
  GH.db.recent = {}
  GH.db.seqIndex = 0
  return #list, long
end

function GH.AddMessage(text)
  local line = clip(text)
  if line == "" then return false end
  GH.db.messages[#GH.db.messages + 1] = newMessage(line)
  return true
end

function GH.SetMessageText(i, text)
  local m, line = GH.db.messages[i], clip(text)
  if not m or line == "" then return false end
  m.text = line
  return true
end

function GH.DeleteMessage(i)
  table.remove(GH.db.messages, i)
end

-- Move message i by delta rows (clamped). Returns its new position.
function GH.MoveMessage(i, delta)
  local msgs = GH.db.messages
  local j = math.max(1, math.min(#msgs, i + delta))
  if j == i then return i end
  local m = table.remove(msgs, i)
  table.insert(msgs, j, m)
  return j
end

function GH.EnabledCount()
  local n = 0
  for _, m in ipairs(GH.db.messages) do if m.enabled then n = n + 1 end end
  return n
end

function GH.IsRecent(id)
  for _, r in ipairs(GH.db.recent) do if r == id then return true end end
  return false
end

-- Priority weight: top row = 3x, bottom row = 1x; favorites are multiplied again.
local function weight(i, n, m)
  local w = 1 + 2 * (n - i) / math.max(n - 1, 1)
  if m.fav then w = w * FAV_WEIGHT end
  return w
end

-- Pick the next message. Returns text, id (nil if nothing is enabled).
function GH.PickMessage()
  local msgs = GH.db.messages
  local n = #msgs
  local enabled = {}
  for i, m in ipairs(msgs) do if m.enabled then enabled[#enabled + 1] = i end end
  if #enabled == 0 then return nil end

  local idx
  if GH.db.sequential then
    local start = GH.db.seqIndex or 0
    for step = 1, n do
      local i = ((start + step - 1) % n) + 1
      if msgs[i].enabled then idx = i; break end
    end
    GH.db.seqIndex = idx
  else
    GH.db.recent = GH.db.recent or {}
    local window = math.min(20, math.floor(#enabled / 2))
    local cand, total = {}, 0
    for _, i in ipairs(enabled) do
      if not GH.IsRecent(msgs[i].id) then
        local w = weight(i, n, msgs[i])
        cand[#cand + 1] = { i, w }
        total = total + w
      end
    end
    if #cand == 0 then -- everything was used recently: start over with all enabled
      for _, i in ipairs(enabled) do
        local w = weight(i, n, msgs[i])
        cand[#cand + 1] = { i, w }
        total = total + w
      end
    end
    local r = math.random() * total
    idx = cand[#cand][1]
    for _, cw in ipairs(cand) do
      r = r - cw[2]
      if r <= 0 then idx = cw[1]; break end
    end
    table.insert(GH.db.recent, msgs[idx].id)
    while #GH.db.recent > window do table.remove(GH.db.recent, 1) end
  end
  return msgs[idx].text, msgs[idx].id
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

-- Find a message by id. Returns message, position.
function GH.FindMessage(id)
  for i, m in ipairs(GH.db.messages) do
    if m.id == id then return m, i end
  end
end

---------------------------------------------------------------------------
-- Preview prompt flow
--   Prompt  : a target is due -> pick a message and show the preview
--   Next    : pick another random message (also marked as used)
--   Remove  : take the shown message out of rotation (disable it) and show the next
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
  if GH.EnabledCount() == 0 then return end
  local _, ok = channelId(t)
  if not ok then
    GH.Print("You are not in channel '" .. tostring(t.channel) .. "'. Skipping it for this cycle.")
    t.lastSent = GetTime()
    return
  end
  local text, id = GH.PickMessage()
  if not text then return end
  GH.pending = { target = t, msg = text, id = id }
  if GH.ShowPrompt then GH.ShowPrompt() end
  if GH.UpdateUI then GH.UpdateUI() end
end

function GH.Next()
  if not GH.pending then return end
  local text, id = GH.PickMessage()
  if text then GH.pending.msg, GH.pending.id = text, id end
  if GH.ShowPrompt then GH.ShowPrompt() end
end

-- Favorite or un-favorite the message shown in the preview.
function GH.SetPendingFavorite(on)
  local p = GH.pending
  if not p then return end
  local m = GH.FindMessage(p.id)
  if m then m.fav = on and true or false end
  if GH.RefreshConfig then GH.RefreshConfig() end
end

-- Take the shown message out of rotation (it is disabled, not deleted, so you can
-- re-enable it on the Messages tab) and move straight on to another one.
function GH.RemovePending()
  local p = GH.pending
  if not p then return end
  local m = GH.FindMessage(p.id)
  if m then m.enabled = false end
  if GH.RefreshConfig then GH.RefreshConfig() end
  if GH.EnabledCount() == 0 then
    GH.Print("No enabled messages left. Add or re-enable some on the Messages tab.")
    p.target.lastSent = GetTime()
    clearPending()
    return
  end
  GH.Next()
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
-- Init on PLAYER_LOGIN (SavedVariables are loaded by then). This does not depend on
-- the addon folder name matching, unlike an ADDON_LOADED name check.
local inited = false
local function Init()
  if inited then return end
  inited = true
  -- `time` is not available in every client build, so pick whichever clock exists.
  local seed = (GetServerTime and GetServerTime()) or (time and time()) or math.floor(GetTime() * 1000)
  if math.randomseed then math.randomseed(seed) end
  GH.InitDB()
  GH.MigrateMessages()
  -- lastSent uses GetTime(), which resets each session: make every target due after min wait.
  local now = GetTime()
  for _, t in ipairs(GH.db.targets) do t.lastSent = now - t.interval; t.group = nil end
  if GH.BuildUI then
    local ok, err = pcall(GH.BuildUI)
    if not ok then
      GH.Print("|cffff4040UI failed to build:|r " .. tostring(err))
    end
  else
    GH.Print("|cffff4040UI.lua did not load.|r")
  end
end
GH.Init = Init

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", Init)
-- If the addon was enabled/reloaded after login, PLAYER_LOGIN will not fire again.
if IsLoggedIn and IsLoggedIn() then Init() end

SLASH_GUILDHAWK1 = "/gh"
SLASH_GUILDHAWK2 = "/guildhawk"
SlashCmdList["GUILDHAWK"] = function(arg)
  Init()
  arg = (arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if arg == "start" then
    GH.db.running = true; GH.Print("Started.")
  elseif arg == "stop" then
    GH.db.running = false; GH.Print("Stopped.")
  elseif arg == "send" then
    GH.SendNext()
  elseif arg == "status" then
    GH.Print((GH.db.running and "Running" or "Stopped") .. ", " .. GH.EnabledCount() .. " of " .. #GH.db.messages .. " messages enabled.")
    local now = GetTime()
    for _, t in ipairs(GH.db.targets) do
      local left = math.max(0, t.interval - (now - (t.lastSent or 0)))
      GH.Print(string.format("  %s: %s, next in %ds", GH.TargetLabel(t), t.enabled and "on" or "off", left))
    end
  else
    if GH.ToggleConfig then GH.ToggleConfig()
    else GH.Print("|cffff4040The settings window is not available (UI failed to load).|r") end
  end
  if GH.UpdateUI then GH.UpdateUI() end
end
