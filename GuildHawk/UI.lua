-- GuildHawk: UI (Ready button + config window)
local GH = GuildHawk

local ready, cfg
local KINDS = { "CHANNEL", "SAY", "YELL" }
local GROUPS = { "-", "A", "B", "C", "D" } -- sync groups; "-" means its own timer

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
    ready:SetText("Review post: " .. GH.pending.unit.label)
    ready:SetAlpha(1)
    return
  end
  local due = GH.NextDue()
  if due then
    ready:SetText("Review " .. due.label)
    ready:SetAlpha(1)
  else
    local now, soon = GetTime(), nil
    for _, un in ipairs(GH.Units()) do
      local left = un.interval - (now - un.lastSent)
      if not soon or left < soon then soon = left end
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
  prompt:SetSize(420, 196)
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

  prompt.fav = CreateFrame("CheckButton", nil, prompt, "UICheckButtonTemplate")
  prompt.fav:SetSize(24, 24)
  prompt.fav:SetPoint("BOTTOMLEFT", 14, 46)
  local favLabel = prompt:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  favLabel:SetPoint("LEFT", prompt.fav, "RIGHT", 2, 0)
  favLabel:SetText("Favorite this message")
  prompt.fav:SetScript("OnClick", function(self) GH.SetPendingFavorite(self:GetChecked()) end)

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
  prompt.title:SetText("Post to " .. p.unit.label .. "?")
  prompt.msg:SetText(p.msg)
  local m = GH.FindMessage(p.id)
  prompt.fav:SetChecked(m and m.fav or false)
  prompt:Show()
end

function GH.HidePrompt()
  if prompt then prompt:Hide() end
end

---------------------------------------------------------------------------
-- Config window: tabs "Messages" and "Channels", plus a bulk-import popup
---------------------------------------------------------------------------
local ROWS, ROW_H = 12, 24
local msgRows, chanRows = {}, {}
local msgPanel, chanPanel, importFrame
local tabButtons = {}
local listOffset, editIndex, refreshing = 0, nil, false
local search, favOnly = "", false

local function flatButton(parent, w, h, text)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, h)
  b:SetText(text)
  return b
end

-- ---- Channels tab ---------------------------------------------------------
local function makeChannelRow(i)
  local r = CreateFrame("Frame", nil, chanPanel)
  r:SetSize(520, 24)
  r:SetPoint("TOPLEFT", chanPanel, "TOPLEFT", 6, -62 - (i - 1) * 26)

  r.enable = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
  r.enable:SetPoint("LEFT", 0, 0)
  r.enable:SetSize(24, 24)

  r.kind = flatButton(r, 70, 22, "")
  r.kind:SetPoint("LEFT", r.enable, "RIGHT", 4, 0)

  r.group = flatButton(r, 36, 22, "-")
  r.group:SetPoint("LEFT", r.kind, "RIGHT", 6, 0)
  r.group:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Sync group", 1, 1, 1)
    GameTooltip:AddLine("Channels in the same group (A-D) share ONE timer and post the same message together. \"-\" = its own timer.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  r.group:SetScript("OnLeave", function() GameTooltip:Hide() end)

  r.channel = CreateFrame("EditBox", nil, r, "InputBoxTemplate")
  r.channel:SetSize(130, 20)
  r.channel:SetPoint("LEFT", r.group, "RIGHT", 12, 0)
  r.channel:SetAutoFocus(false)

  r.interval = CreateFrame("EditBox", nil, r, "InputBoxTemplate")
  r.interval:SetSize(50, 20)
  r.interval:SetPoint("LEFT", r.channel, "RIGHT", 12, 0)
  r.interval:SetAutoFocus(false)
  r.interval:SetNumeric(true)

  r.secs = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  r.secs:SetPoint("LEFT", r.interval, "RIGHT", 4, 0)
  r.secs:SetText("sec")

  r.del = flatButton(r, 22, 22, "X")
  r.del:SetPoint("LEFT", r.secs, "RIGHT", 10, 0)

  r.enable:SetScript("OnClick", function(self) r.target.enabled = self:GetChecked() and true or false; GH.UpdateUI() end)
  r.kind:SetScript("OnClick", function()
    local k = r.target.kind
    for n, v in ipairs(KINDS) do if v == k then k = KINDS[n % #KINDS + 1]; break end end
    r.target.kind = k
    GH.RefreshConfig()
  end)
  r.group:SetScript("OnClick", function()
    local t = r.target
    local cur = t.group or "-"
    local nxt = GROUPS[1]
    for n, g in ipairs(GROUPS) do if g == cur then nxt = GROUPS[n % #GROUPS + 1]; break end end
    t.group = (nxt ~= "-") and nxt or nil
    if t.group then -- adopt the interval and timing of the group's existing members
      for _, o in ipairs(GH.db.targets) do
        if o ~= t and o.group == t.group then t.interval, t.lastSent = o.interval, o.lastSent; break end
      end
    end
    GH.RefreshConfig()
    GH.UpdateUI()
  end)
  r.channel:SetScript("OnEnterPressed", function(self) r.target.channel = self:GetText(); self:ClearFocus() end)
  r.channel:SetScript("OnEditFocusLost", function(self) r.target.channel = self:GetText() end)
  local function commitInterval(self)
    local t = r.target
    t.interval = GH.ClampInterval(self:GetText())
    self:SetText(t.interval)
    if t.group then -- one timer per group: keep every member on the same interval
      for _, o in ipairs(GH.db.targets) do if o.group == t.group then o.interval = t.interval end end
      GH.RefreshConfig()
    end
  end
  r.interval:SetScript("OnEnterPressed", function(self) commitInterval(self); self:ClearFocus() end)
  r.interval:SetScript("OnEditFocusLost", commitInterval)
  r.del:SetScript("OnClick", function()
    for n, t in ipairs(GH.db.targets) do if t == r.target then table.remove(GH.db.targets, n); break end end
    GH.RefreshConfig()
  end)
  return r
end

local function RefreshChannels()
  if not chanPanel then return end
  chanPanel.run:SetText(GH.db.running and "Stop" or "Start")
  chanPanel.seq:SetChecked(GH.db.sequential)
  for i, t in ipairs(GH.db.targets) do
    chanRows[i] = chanRows[i] or makeChannelRow(i)
    local r = chanRows[i]
    r.target = t
    r:Show()
    r.enable:SetChecked(t.enabled)
    r.kind:SetText(t.kind)
    r.group:SetText(t.group or "-")
    if not r.channel:HasFocus() then r.channel:SetText(t.channel or "") end
    if t.kind == "CHANNEL" then r.channel:Show() else r.channel:Hide() end
    if not r.interval:HasFocus() then r.interval:SetText(t.interval) end
  end
  for i = #GH.db.targets + 1, #chanRows do chanRows[i]:Hide() end
end

local function BuildChannelsPanel()
  chanPanel = CreateFrame("Frame", nil, cfg)
  chanPanel:SetPoint("TOPLEFT", 14, -66)
  chanPanel:SetPoint("BOTTOMRIGHT", -14, 14)

  chanPanel.run = flatButton(chanPanel, 80, 22, "Start")
  chanPanel.run:SetPoint("TOPLEFT", 6, 0)
  chanPanel.run:SetScript("OnClick", function() GH.db.running = not GH.db.running; GH.UpdateUI() end)

  chanPanel.seq = CreateFrame("CheckButton", nil, chanPanel, "UICheckButtonTemplate")
  chanPanel.seq:SetSize(24, 24)
  chanPanel.seq:SetPoint("LEFT", chanPanel.run, "RIGHT", 16, 0)
  chanPanel.seq:SetScript("OnClick", function(self) GH.db.sequential = self:GetChecked() and true or false end)
  local sl = chanPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  sl:SetPoint("LEFT", chanPanel.seq, "RIGHT", 2, 0)
  sl:SetText("Post messages in list order instead of random")

  local th = chanPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  th:SetPoint("TOPLEFT", 6, -42)
  th:SetText("Channels:  on / type / sync group / channel name / interval (minimum 60 seconds)")

  local hint = chanPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 6, -62 - 8 * 26 - 8)
  hint:SetWidth(500)
  hint:SetJustifyH("LEFT")
  hint:SetText("Sync groups: give two or more channels the same letter (A-D) and they share one timer. When it is due you get one preview, and Okay posts that same message to every channel in the group. Channels left on \"-\" keep their own timers.")

  local add = flatButton(chanPanel, 110, 22, "Add channel")
  add:SetPoint("BOTTOMLEFT", 6, 6)
  add:SetScript("OnClick", function()
    if #GH.db.targets >= 8 then return end
    table.insert(GH.db.targets, { kind = "CHANNEL", channel = "General", interval = 180, enabled = true, lastSent = GetTime() - 180 })
    GH.RefreshConfig()
  end)

  local review = flatButton(chanPanel, 130, 22, "Review next due")
  review:SetPoint("BOTTOMRIGHT", -6, 6)
  review:SetScript("OnClick", function() GH.SendNext() end)
end

-- ---- Messages tab ---------------------------------------------------------
local function viewList()
  local view, q = {}, search:lower()
  for i, m in ipairs(GH.db.messages) do
    if (not favOnly or m.fav) and (q == "" or m.text:lower():find(q, 1, true)) then
      view[#view + 1] = i
    end
  end
  return view
end

local function filtered() return search ~= "" or favOnly end

local function PopulateRows(view)
  local msgs = GH.db.messages
  for r = 1, ROWS do
    local row = msgRows[r]
    local idx = view[listOffset + r]
    local m = idx and msgs[idx]
    if m then
      row.idx = idx
      row:Show()
      row.enable:SetChecked(m.enabled)
      row.num:SetText(idx)
      row.fs:SetText(m.text)
      if not m.enabled then row.fs:SetTextColor(0.5, 0.5, 0.5)
      elseif GH.IsRecent(m.id) then row.fs:SetTextColor(0.75, 0.75, 0.55)
      else row.fs:SetTextColor(1, 1, 1) end
      row.star:SetAlpha(m.fav and 1 or 0.2)
      row.sel:SetShown(idx == editIndex)
      local canMove = not filtered()
      row.up:SetAlpha(canMove and 1 or 0.3)
      row.down:SetAlpha(canMove and 1 or 0.3)
    else
      row.idx = nil
      row:Hide()
    end
  end
end

local function RefreshMessages()
  if not msgPanel then return end
  local view = viewList()
  local maxOffset = math.max(0, #view - ROWS)
  if listOffset > maxOffset then listOffset = maxOffset end
  refreshing = true
  msgPanel.slider:SetMinMaxValues(0, maxOffset)
  msgPanel.slider:SetValue(listOffset)
  refreshing = false
  msgPanel.slider:SetShown(maxOffset > 0)
  PopulateRows(view)
  local total = #GH.db.messages
  msgPanel.count:SetText(string.format("%d shown / %d total / %d enabled", #view, total, GH.EnabledCount()))
  msgPanel.save:SetAlpha(editIndex and 1 or 0.4)
end

local function selectMessage(idx)
  editIndex = idx
  local m = idx and GH.db.messages[idx]
  msgPanel.edit:SetText(m and m.text or "")
  if m then msgPanel.edit:SetFocus() end
  RefreshMessages()
end

local function makeMessageRow(r)
  local row = CreateFrame("Frame", nil, msgPanel.list)
  row:SetSize(484, ROW_H)
  row:SetPoint("TOPLEFT", msgPanel.list, "TOPLEFT", 0, -(r - 1) * ROW_H)

  row.sel = row:CreateTexture(nil, "BACKGROUND")
  row.sel:SetAllPoints()
  row.sel:SetColorTexture(1, 0.82, 0, 0.15)
  row.sel:Hide()

  row.enable = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
  row.enable:SetSize(22, 22)
  row.enable:SetPoint("LEFT", 0, 0)
  row.enable:SetScript("OnClick", function(self)
    local m = GH.db.messages[row.idx]
    if m then m.enabled = self:GetChecked() and true or false end
    RefreshMessages()
  end)

  row.favBtn = CreateFrame("Button", nil, row)
  row.favBtn:SetSize(20, 20)
  row.favBtn:SetPoint("LEFT", row.enable, "RIGHT", 2, 0)
  row.star = row.favBtn:CreateTexture(nil, "ARTWORK")
  row.star:SetAllPoints()
  row.star:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
  row.favBtn:SetScript("OnClick", function()
    local m = GH.db.messages[row.idx]
    if m then m.fav = not m.fav end
    RefreshMessages()
  end)
  row.favBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Favorite: picked about 3x more often")
    GameTooltip:Show()
  end)
  row.favBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  row.num = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  row.num:SetPoint("LEFT", row.favBtn, "RIGHT", 4, 0)
  row.num:SetWidth(26)
  row.num:SetJustifyH("RIGHT")

  row.del = flatButton(row, 22, 20, "X")
  row.del:SetPoint("RIGHT", 0, 0)
  row.down = flatButton(row, 22, 20, "v")
  row.down:SetPoint("RIGHT", row.del, "LEFT", -2, 0)
  row.up = flatButton(row, 22, 20, "^")
  row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)

  row.textBtn = CreateFrame("Button", nil, row)
  row.textBtn:SetPoint("LEFT", row.num, "RIGHT", 6, 0)
  row.textBtn:SetPoint("RIGHT", row.up, "LEFT", -6, 0)
  row.textBtn:SetHeight(ROW_H)
  row.textBtn:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
  row.fs = row.textBtn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  row.fs:SetAllPoints()
  row.fs:SetJustifyH("LEFT")
  row.fs:SetWordWrap(false)

  row.textBtn:SetScript("OnClick", function() selectMessage(row.idx) end)
  row.textBtn:SetScript("OnEnter", function(self)
    local m = GH.db.messages[row.idx]
    if not m then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(m.text, 1, 1, 1, 1, true)
    GameTooltip:AddLine("Click to edit", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  row.textBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local function move(delta)
    if filtered() or not row.idx then return end
    local step = IsShiftKeyDown() and 10 or 1
    local from = row.idx
    local to = GH.MoveMessage(from, delta * step)
    if editIndex == from then editIndex = to end
    RefreshMessages()
  end
  row.up:SetScript("OnClick", function() move(-1) end)
  row.down:SetScript("OnClick", function() move(1) end)
  row.del:SetScript("OnClick", function()
    if not row.idx then return end
    GH.DeleteMessage(row.idx)
    if editIndex == row.idx then editIndex = nil; msgPanel.edit:SetText("")
    elseif editIndex and editIndex > row.idx then editIndex = editIndex - 1 end
    RefreshMessages()
  end)
  return row
end

local function BuildImportFrame()
  importFrame = CreateFrame("Frame", "GuildHawkImport", UIParent, "BackdropTemplate")
  importFrame:SetSize(480, 340)
  importFrame:SetPoint("CENTER")
  importFrame:SetFrameStrata("FULLSCREEN_DIALOG")
  importFrame:SetMovable(true)
  importFrame:EnableMouse(true)
  importFrame:RegisterForDrag("LeftButton")
  importFrame:SetScript("OnDragStart", importFrame.StartMoving)
  importFrame:SetScript("OnDragStop", importFrame.StopMovingOrSizing)
  backdrop(importFrame)
  importFrame:Hide()
  tinsert(UISpecialFrames, "GuildHawkImport")

  local title = importFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -14)
  title:SetText("Bulk import messages")

  local hint = importFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", 20, -40)
  hint:SetWidth(440)
  hint:SetJustifyH("LEFT")
  hint:SetText("Paste your messages below. Every line break starts a new message. Blank lines are ignored and lines over 255 characters are cut.")

  local scroll = CreateFrame("ScrollFrame", "GuildHawkImportScroll", importFrame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 20, -78)
  scroll:SetSize(410, 190)
  local box = CreateFrame("EditBox", nil, scroll)
  box:SetMultiLine(true)
  box:SetAutoFocus(false)
  box:SetFontObject(ChatFontNormal)
  box:SetWidth(400)
  box:SetMaxLetters(0)
  box:SetScript("OnEscapePressed", box.ClearFocus)
  scroll:SetScrollChild(box)
  importFrame.box = box

  local status = importFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  status:SetPoint("TOPLEFT", 20, -274)
  importFrame.status = status
  box:SetScript("OnTextChanged", function(self)
    local list, long = GH.ParseMessages(self:GetText())
    status:SetText(string.format("%d messages detected%s", #list, long > 0 and (", " .. long .. " will be cut to 255 characters") or ""))
  end)

  local confirmReplace = false
  local function done(n, long, verb)
    GH.Print(string.format("%s %d messages%s.", verb, n, long > 0 and (" (" .. long .. " cut to 255)") or ""))
    box:SetText("")
    importFrame:Hide()
    editIndex, listOffset = nil, 0
    GH.RefreshConfig()
  end

  local append = flatButton(importFrame, 120, 24, "Add to list")
  append:SetPoint("BOTTOMLEFT", 20, 16)
  append:SetScript("OnClick", function()
    local n, long = GH.ImportMessages(box:GetText(), true)
    done(n, long, "Added")
  end)

  local replace = flatButton(importFrame, 150, 24, "Replace whole list")
  replace:SetPoint("LEFT", append, "RIGHT", 8, 0)
  replace:SetScript("OnClick", function(self)
    if #GH.db.messages > 0 and not confirmReplace then
      confirmReplace = true
      self:SetText("Click again to confirm")
      return
    end
    local n, long = GH.ImportMessages(box:GetText(), false)
    done(n, long, "Imported")
  end)
  importFrame:SetScript("OnHide", function() confirmReplace = false; replace:SetText("Replace whole list") end)

  local cancel = flatButton(importFrame, 90, 24, "Cancel")
  cancel:SetPoint("BOTTOMRIGHT", -20, 16)
  cancel:SetScript("OnClick", function() importFrame:Hide() end)
end

local function BuildMessagesPanel()
  msgPanel = CreateFrame("Frame", nil, cfg)
  msgPanel:SetPoint("TOPLEFT", 14, -66)
  msgPanel:SetPoint("BOTTOMRIGHT", -14, 14)

  local imp = flatButton(msgPanel, 120, 22, "Bulk import...")
  imp:SetPoint("TOPLEFT", 6, 0)
  imp:SetScript("OnClick", function() importFrame:Show(); importFrame.box:SetFocus() end)

  local sl = msgPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  sl:SetPoint("LEFT", imp, "RIGHT", 14, 0)
  sl:SetText("Search:")
  local sb = CreateFrame("EditBox", nil, msgPanel, "InputBoxTemplate")
  sb:SetSize(130, 20)
  sb:SetPoint("LEFT", sl, "RIGHT", 8, 0)
  sb:SetAutoFocus(false)
  sb:SetScript("OnTextChanged", function(self) search = self:GetText() or ""; listOffset = 0; RefreshMessages() end)
  sb:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  sb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

  local fo = CreateFrame("CheckButton", nil, msgPanel, "UICheckButtonTemplate")
  fo:SetSize(22, 22)
  fo:SetPoint("LEFT", sb, "RIGHT", 10, 0)
  fo:SetScript("OnClick", function(self) favOnly = self:GetChecked() and true or false; listOffset = 0; RefreshMessages() end)
  local fl = msgPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  fl:SetPoint("LEFT", fo, "RIGHT", 0, 0)
  fl:SetText("Favorites only")

  msgPanel.count = msgPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  msgPanel.count:SetPoint("TOPLEFT", 6, -28)

  msgPanel.list = CreateFrame("Frame", nil, msgPanel)
  msgPanel.list:SetPoint("TOPLEFT", 0, -46)
  msgPanel.list:SetSize(484, ROWS * ROW_H)
  msgPanel.list:EnableMouseWheel(true)
  msgPanel.list:SetScript("OnMouseWheel", function(_, delta)
    msgPanel.slider:SetValue(math.max(0, listOffset - delta * 3))
  end)
  local bg = msgPanel.list:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.3)

  local slider = CreateFrame("Slider", nil, msgPanel)
  slider:SetOrientation("VERTICAL")
  slider:SetSize(16, ROWS * ROW_H)
  slider:SetPoint("TOPLEFT", msgPanel.list, "TOPRIGHT", 4, 0)
  slider:SetMinMaxValues(0, 0)
  slider:SetValueStep(1)
  slider:SetValue(0)
  slider:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  local thumb = slider:GetThumbTexture()
  if thumb then thumb:SetSize(16, 24) end
  local track = slider:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints()
  track:SetColorTexture(1, 1, 1, 0.08)
  slider:SetScript("OnValueChanged", function(_, value)
    if refreshing then return end
    listOffset = math.floor(value + 0.5)
    PopulateRows(viewList())
  end)
  msgPanel.slider = slider

  for r = 1, ROWS do msgRows[r] = makeMessageRow(r) end

  local ey = -(46 + ROWS * ROW_H + 12)
  local el = msgPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  el:SetPoint("TOPLEFT", 6, ey)
  el:SetText("Click a message above to edit it, or type a new one:")

  -- Multi-line edit area (the message is still one chat line; line breaks become spaces on save)
  local box = CreateFrame("Frame", nil, msgPanel, "BackdropTemplate")
  box:SetSize(490, 58)
  box:SetPoint("TOPLEFT", 8, ey - 18)
  box:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  box:SetBackdropColor(0, 0, 0, 0.6)
  box:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

  local scroll = CreateFrame("ScrollFrame", "GuildHawkEditScroll", box, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 6, -6)
  scroll:SetPoint("BOTTOMRIGHT", -26, 6)

  local eb = CreateFrame("EditBox", nil, scroll)
  eb:SetMultiLine(true)
  eb:SetAutoFocus(false)
  eb:SetFontObject(ChatFontNormal)
  eb:SetWidth(452)
  eb:SetHeight(44)
  eb:SetMaxLetters(255)
  scroll:SetScrollChild(eb)
  scroll:EnableMouse(true)
  scroll:SetScript("OnMouseDown", function() eb:SetFocus() end)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  -- keep the cursor line visible while typing
  eb:SetScript("OnCursorChanged", function(_, _, y, _, h)
    y = -y
    local top, view = scroll:GetVerticalScroll(), scroll:GetHeight()
    if y < top then scroll:SetVerticalScroll(y)
    elseif y + h > top + view then scroll:SetVerticalScroll(y + h - view) end
  end)
  local counter = msgPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  counter:SetPoint("TOPRIGHT", -8, ey)
  eb:SetScript("OnTextChanged", function(self) counter:SetText(#self:GetText() .. " / 255") end)
  msgPanel.edit = eb

  local save = flatButton(msgPanel, 90, 22, "Save edit")
  save:SetPoint("TOPLEFT", 6, ey - 86)
  save:SetScript("OnClick", function()
    if editIndex and GH.SetMessageText(editIndex, eb:GetText()) then
      GH.Print("Message updated.")
    end
    eb:ClearFocus()
    RefreshMessages()
  end)
  msgPanel.save = save

  local addNew = flatButton(msgPanel, 110, 22, "Add as new")
  addNew:SetPoint("LEFT", save, "RIGHT", 6, 0)
  addNew:SetScript("OnClick", function()
    if GH.AddMessage(eb:GetText()) then
      eb:SetText(""); editIndex = nil
      search, favOnly = "", false
      sb:SetText(""); fo:SetChecked(false)
      listOffset = math.max(0, #GH.db.messages - ROWS)
    end
    eb:ClearFocus()
    RefreshMessages()
  end)

  local clearAll = flatButton(msgPanel, 100, 22, "Clear list")
  clearAll:SetPoint("TOPRIGHT", -6, ey - 86)
  local confirm = false
  clearAll:SetScript("OnClick", function(self)
    if not confirm then confirm = true; self:SetText("Sure?"); return end
    confirm = false; self:SetText("Clear list")
    GH.db.messages = {}; GH.db.recent = {}; GH.db.seqIndex = 0
    editIndex, listOffset = nil, 0
    eb:SetText("")
    RefreshMessages()
  end)
  clearAll:SetScript("OnHide", function(self) confirm = false; self:SetText("Clear list") end)

  local tip = msgPanel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  tip:SetPoint("TOPLEFT", 6, ey - 116)
  tip:SetWidth(500)
  tip:SetJustifyH("LEFT")
  tip:SetText("Top rows are picked more often (top = 3x the bottom). Favorites get another 3x. Unticked messages are never used. ^ / v move a row; hold Shift to move 10. Moving is off while a search or filter is active.")
end

-- ---- Window ---------------------------------------------------------------
local function ShowTab(n)
  GH.cfgTab = n
  msgPanel:SetShown(n == 1)
  chanPanel:SetShown(n == 2)
  for i, b in ipairs(tabButtons) do
    if i == n then b:Disable() else b:Enable() end
  end
  GH.RefreshConfig()
end

function GH.RefreshConfig()
  if not cfg then return end
  RefreshChannels()
  RefreshMessages()
end

local function BuildConfig()
  cfg = CreateFrame("Frame", "GuildHawkConfig", UIParent, "BackdropTemplate")
  cfg:SetSize(560, 600)
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

  local names = { "Messages", "Channels" }
  for i, name in ipairs(names) do
    local b = flatButton(cfg, 110, 24, name)
    b:SetPoint("TOPLEFT", 20 + (i - 1) * 114, -38)
    b:SetScript("OnClick", function() ShowTab(i) end)
    tabButtons[i] = b
  end

  BuildImportFrame()
  BuildMessagesPanel()
  BuildChannelsPanel()
  cfg:SetScript("OnShow", function() ShowTab(GH.cfgTab or 1) end)
end

function GH.ToggleConfig()
  if not cfg then return end
  if cfg:IsShown() then cfg:Hide() else cfg:Show() end
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
