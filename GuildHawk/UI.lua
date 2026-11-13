-- GuildHawk: UI (Ready button + config window)
local GH = GuildHawk

local ready, cfg
local rows = {}
local KINDS = { "CHANNEL", "SAY", "YELL" }

local function backdrop(frame)
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 24,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
  })
end

---------------------------------------------------------------------------
-- Ready button
---------------------------------------------------------------------------
local function BuildReady()
  ready = CreateFrame("Button", "GuildHawkReadyButton", UIParent, "UIPanelButtonTemplate")
  ready:SetSize(190, 32)
  local pos = GH.db.readyPos
  if pos then
    ready:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  else
    ready:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
  end
  ready:SetMovable(true)
  ready:SetClampedToScreen(true)
  ready:EnableMouse(true)
  ready:RegisterForClicks("LeftButtonUp")
  ready:RegisterForDrag("LeftButton", "RightButton")
  ready:SetScript("OnDragStart", function(self) self:StartMoving() end)
  ready:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    GH.db.readyPos = { point, relPoint, x, y }
  end)
  ready:SetScript("OnClick", function() GH.Prompt() end)
  ready:SetText("Guild Hawk")

  local elapsed = 0
  ready:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 1 then return end
    elapsed = 0
    if not GH.pending then
      GH.Prompt()
      if GH.pending then PlaySound(SOUNDKIT and SOUNDKIT.TELL_MESSAGE or 3081) end
    end
    GH.UpdateUI()
  end)
end

function GH.UpdateUI()
  if not ready then return end
  if not GH.db.running then
    ready:SetText("Guild Hawk: stopped")
    ready:SetAlpha(0.6)
    return
  end
  if GH.pending then
    ready:SetText("Review post: " .. GH.TargetLabel(GH.pending.target))
    ready:SetAlpha(1)
    return
  end
  local t = GH.NextDue()
  if t then
    ready:SetText("Review " .. GH.TargetLabel(t))
    ready:SetAlpha(1)
  else
    local now, soon = GetTime(), nil
    for _, tt in ipairs(GH.db.targets) do
      if tt.enabled then
        local left = tt.interval - (now - (tt.lastSent or 0))
        if not soon or left < soon then soon = left end
      end
    end
    ready:SetText(soon and string.format("Next in %d:%02d", soon / 60, soon % 60) or "No targets")
    ready:SetAlpha(0.6)
  end
  if cfg and cfg:IsShown() then GH.RefreshConfig() end
end

---------------------------------------------------------------------------
-- Preview prompt (message + channel + 5 buttons)
---------------------------------------------------------------------------
local prompt

local function BuildPrompt()
  prompt = CreateFrame("Frame", "GuildHawkPrompt", UIParent, "BackdropTemplate")
  prompt:SetSize(420, 170)
  prompt:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  prompt:SetFrameStrata("DIALOG")
  prompt:SetMovable(true)
  prompt:EnableMouse(true)
  prompt:RegisterForDrag("LeftButton")
  prompt:SetScript("OnDragStart", prompt.StartMoving)
  prompt:SetScript("OnDragStop", prompt.StopMovingOrSizing)
  backdrop(prompt)
  prompt:Hide()

  prompt.title = prompt:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  prompt.title:SetPoint("TOP", 0, -14)

  prompt.msg = prompt:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  prompt.msg:SetPoint("TOPLEFT", 20, -42)
  prompt.msg:SetWidth(380)
  prompt.msg:SetJustifyH("LEFT")
  prompt.msg:SetJustifyV("TOP")
  prompt.msg:SetHeight(70)

  local defs = {
    { "Next",       function() GH.Next() end },
    { "Okay",       function() GH.Approve() end },
    { "Skip",       function() GH.Skip() end },
    { "Cancel",     function() GH.CancelTarget() end },
    { "Cancel All", function() GH.CancelAll() end },
  }
  local prev
  for i, d in ipairs(defs) do
    local b = CreateFrame("Button", nil, prompt, "UIPanelButtonTemplate")
    b:SetSize(76, 24)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("BOTTOMLEFT", 12, 16) end
    b:SetText(d[1])
    b:SetScript("OnClick", d[2])
    prev = b
  end
end

function GH.ShowPrompt()
  local p = GH.pending
  if not p or not prompt then return end
  prompt.title:SetText("Post to " .. GH.TargetLabel(p.target) .. "?")
  prompt.msg:SetText(p.msg)
  prompt:Show()
end

function GH.HidePrompt()
  if prompt then prompt:Hide() end
end

---------------------------------------------------------------------------
-- Config window
---------------------------------------------------------------------------
local function makeRow(i)
  local r = CreateFrame("Frame", nil, cfg)
  r:SetSize(420, 24)
  r:SetPoint("TOPLEFT", cfg, "TOPLEFT", 20, -250 - (i - 1) * 26)

  r.enable = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
  r.enable:SetPoint("LEFT", 0, 0)
  r.enable:SetSize(24, 24)

  r.kind = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
  r.kind:SetSize(70, 22)
  r.kind:SetPoint("LEFT", r.enable, "RIGHT", 4, 0)

  r.channel = CreateFrame("EditBox", nil, r, "InputBoxTemplate")
  r.channel:SetSize(110, 20)
  r.channel:SetPoint("LEFT", r.kind, "RIGHT", 12, 0)
  r.channel:SetAutoFocus(false)

  r.interval = CreateFrame("EditBox", nil, r, "InputBoxTemplate")
  r.interval:SetSize(50, 20)
  r.interval:SetPoint("LEFT", r.channel, "RIGHT", 12, 0)
  r.interval:SetAutoFocus(false)
  r.interval:SetNumeric(true)

  r.secs = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  r.secs:SetPoint("LEFT", r.interval, "RIGHT", 4, 0)
  r.secs:SetText("sec")

  r.del = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
  r.del:SetSize(22, 22)
  r.del:SetPoint("LEFT", r.secs, "RIGHT", 10, 0)
  r.del:SetText("X")

  r.enable:SetScript("OnClick", function(self) r.target.enabled = self:GetChecked() and true or false; GH.UpdateUI() end)
  r.kind:SetScript("OnClick", function()
    local k = r.target.kind
    for n, v in ipairs(KINDS) do if v == k then k = KINDS[n % #KINDS + 1]; break end end
    r.target.kind = k
    GH.RefreshConfig()
  end)
  r.channel:SetScript("OnEnterPressed", function(self) r.target.channel = self:GetText(); self:ClearFocus() end)
  r.channel:SetScript("OnEditFocusLost", function(self) r.target.channel = self:GetText() end)
  local function commitInterval(self)
    r.target.interval = GH.ClampInterval(self:GetText())
    self:SetText(r.target.interval)
  end
  r.interval:SetScript("OnEnterPressed", function(self) commitInterval(self); self:ClearFocus() end)
  r.interval:SetScript("OnEditFocusLost", commitInterval)
  r.del:SetScript("OnClick", function()
    for n, t in ipairs(GH.db.targets) do if t == r.target then table.remove(GH.db.targets, n); break end end
    GH.RefreshConfig()
  end)
  return r
end

function GH.RefreshConfig()
  if not cfg then return end
  cfg.count:SetText(#GH.db.messages .. " messages in pool")
  cfg.run:SetText(GH.db.running and "Stop" or "Start")
  cfg.seq:SetChecked(GH.db.sequential)
  for i, t in ipairs(GH.db.targets) do
    rows[i] = rows[i] or makeRow(i)
    local r = rows[i]
    r.target = t
    r:Show()
    r.enable:SetChecked(t.enabled)
    r.kind:SetText(t.kind)
    r.channel:SetText(t.channel or "")
    if t.kind == "CHANNEL" then r.channel:Show() else r.channel:Hide() end
    if not r.interval:HasFocus() then r.interval:SetText(t.interval) end
  end
  for i = #GH.db.targets + 1, #rows do rows[i]:Hide() end
end

local function BuildConfig()
  cfg = CreateFrame("Frame", "GuildHawkConfig", UIParent, "BackdropTemplate")
  cfg:SetSize(480, 460)
  cfg:SetPoint("CENTER")
  cfg:SetFrameStrata("DIALOG")
  cfg:SetMovable(true)
  cfg:EnableMouse(true)
  cfg:RegisterForDrag("LeftButton")
  cfg:SetScript("OnDragStart", cfg.StartMoving)
  cfg:SetScript("OnDragStop", cfg.StopMovingOrSizing)
  backdrop(cfg)
  cfg:Hide()
  tinsert(UISpecialFrames, "GuildHawkConfig")

  local title = cfg:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -14)
  title:SetText("Guild Hawk")

  local close = CreateFrame("Button", nil, cfg, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)

  cfg.run = CreateFrame("Button", nil, cfg, "UIPanelButtonTemplate")
  cfg.run:SetSize(80, 22)
  cfg.run:SetPoint("TOPLEFT", 20, -40)
  cfg.run:SetScript("OnClick", function()
    GH.db.running = not GH.db.running
    GH.UpdateUI()
  end)

  cfg.count = cfg:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  cfg.count:SetPoint("LEFT", cfg.run, "RIGHT", 12, 0)

  cfg.seq = CreateFrame("CheckButton", nil, cfg, "UICheckButtonTemplate")
  cfg.seq:SetPoint("TOPRIGHT", -110, -38)
  cfg.seq:SetSize(24, 24)
  local seqLabel = cfg:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  seqLabel:SetPoint("LEFT", cfg.seq, "RIGHT", 2, 0)
  seqLabel:SetText("In order")
  cfg.seq:SetScript("OnClick", function(self) GH.db.sequential = self:GetChecked() and true or false end)

  local hint = cfg:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  hint:SetPoint("TOPLEFT", 20, -72)
  hint:SetText("Paste messages below, one per line (max 255 chars each):")

  local scroll = CreateFrame("ScrollFrame", "GuildHawkScroll", cfg, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 20, -90)
  scroll:SetSize(410, 110)
  local box = CreateFrame("EditBox", nil, scroll)
  box:SetMultiLine(true)
  box:SetAutoFocus(false)
  box:SetFontObject(ChatFontNormal)
  box:SetWidth(400)
  box:SetMaxLetters(0)
  box:SetScript("OnEscapePressed", box.ClearFocus)
  scroll:SetScrollChild(box)
  cfg.box = box

  local function doImport(append)
    local n, long = GH.ImportMessages(box:GetText(), append)
    box:SetText("")
    GH.Print(string.format("Imported %d messages%s.", n, long > 0 and (" (" .. long .. " truncated to 255)") or ""))
    GH.RefreshConfig()
  end

  local replace = CreateFrame("Button", nil, cfg, "UIPanelButtonTemplate")
  replace:SetSize(110, 22); replace:SetPoint("TOPLEFT", 20, -208); replace:SetText("Replace pool")
  replace:SetScript("OnClick", function() doImport(false) end)

  local append = CreateFrame("Button", nil, cfg, "UIPanelButtonTemplate")
  append:SetSize(110, 22); append:SetPoint("LEFT", replace, "RIGHT", 6, 0); append:SetText("Append")
  append:SetScript("OnClick", function() doImport(true) end)

  local clear = CreateFrame("Button", nil, cfg, "UIPanelButtonTemplate")
  clear:SetSize(110, 22); clear:SetPoint("LEFT", append, "RIGHT", 6, 0); clear:SetText("Clear pool")
  clear:SetScript("OnClick", function() GH.db.messages = {}; GH.db.recent = {}; GH.RefreshConfig() end)

  local th = cfg:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  th:SetPoint("TOPLEFT", 20, -236)
  th:SetText("Targets: on / type / channel name / interval (min 60s)")

  local add = CreateFrame("Button", nil, cfg, "UIPanelButtonTemplate")
  add:SetSize(110, 22); add:SetPoint("BOTTOMLEFT", 20, 16); add:SetText("Add target")
  add:SetScript("OnClick", function()
    if #GH.db.targets >= 8 then return end
    table.insert(GH.db.targets, { kind = "CHANNEL", channel = "General", interval = 180, enabled = true, lastSent = GetTime() - 180 })
    GH.RefreshConfig()
  end)

  local sendNow = CreateFrame("Button", nil, cfg, "UIPanelButtonTemplate")
  sendNow:SetSize(130, 22); sendNow:SetPoint("BOTTOMRIGHT", -20, 16); sendNow:SetText("Review next due")
  sendNow:SetScript("OnClick", function() GH.SendNext() end)
end

---------------------------------------------------------------------------
-- Minimap button (drag around the rim; click opens the config window)
---------------------------------------------------------------------------
local minimapBtn

local function PlaceMinimapButton()
  local a = math.rad(GH.db.minimapAngle or 200)
  local r = (Minimap:GetWidth() / 2) + 5
  minimapBtn:ClearAllPoints()
  minimapBtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function BuildMinimapButton()
  local b = CreateFrame("Button", "GuildHawkMinimapButton", Minimap)
  minimapBtn = b
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Horn_01")
  icon:SetSize(20, 20)
  icon:SetPoint("TOPLEFT", 7, -6)
  icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")

  b:SetScript("OnClick", function() GH.ToggleConfig() end)

  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local px, py = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      px, py = px / scale, py / scale
      local atan2 = math.atan2 or math.atan
      GH.db.minimapAngle = math.deg(atan2(py - my, px - mx))
      PlaceMinimapButton()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Guild Hawk")
    GameTooltip:AddLine("Click: open settings", 1, 1, 1)
    GameTooltip:AddLine("Drag: move this button", 1, 1, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)

  PlaceMinimapButton()
end

function GH.ToggleConfig()
  if not cfg then return end
  if cfg:IsShown() then cfg:Hide() else GH.RefreshConfig(); cfg:Show() end
end

function GH.BuildUI()
  local steps = {
    { "Ready button", BuildReady },
    { "Prompt", BuildPrompt },
    { "Config window", BuildConfig },
    { "Minimap button", BuildMinimapButton },
  }
  for _, s in ipairs(steps) do
    local ok, err = pcall(s[2])
    if not ok then GH.Print("|cffff4040" .. s[1] .. " failed:|r " .. tostring(err)) end
  end
  pcall(GH.UpdateUI)
  GH.Print("Loaded. /gh to configure, /gh start to begin. Drag the countdown button to move it.")
end
