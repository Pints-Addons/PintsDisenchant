-- Pint's Disenchant: a destroy list for enchanters (Pint's Add-ons)
-- Blizzard requires one hardware click per cast, so every disenchant is a real click on a secure button
-- (the big "Disenchant next" button, its keybind, or a row in the list).

local ADDON = ...
-- Compatibility: WoW Forever runs on the modern game client, where these older functions moved or were renamed.
local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local GetItemQualityColor = GetItemQualityColor or (C_Item and C_Item.GetItemQualityColor)
local IsSpellKnown = IsSpellKnown or (C_SpellBook and C_SpellBook.IsSpellKnown)
local GetSpellInfo = GetSpellInfo or function(s)
	local i = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(s)
	if i then return i.name, nil, i.iconID, i.castTime, i.minRange, i.maxRange, i.spellID, i.originalIconID end
end
local GetNumSkillLines, GetSkillLineInfo = GetNumSkillLines, GetSkillLineInfo
if not GetNumSkillLines and GetProfessions then
	local lines = {}
	GetNumSkillLines = function()
		wipe(lines)
		local p = { GetProfessions() }
		for k = 1, 6 do
			if p[k] then
				local name, _, rank, maxRank = GetProfessionInfo(p[k])
				if name then lines[#lines + 1] = { name, rank, maxRank } end
			end
		end
		return #lines
	end
	GetSkillLineInfo = function(i)
		local l = lines[i]
		if l then return l[1], false, false, l[2], 0, 0, l[3] end
	end
end

local DE_SPELL = 13262
local ROW_H, ROWS_MAX, W, H = 26, 200, 440, 470

BINDING_HEADER_PINTSDISENCHANT = "Pint's Disenchant"
_G["BINDING_NAME_CLICK PintsDisenchantNext:LeftButton"] = "Disenchant next item"

local db
local items, ignoredList = {}, {}
local showIgnored = false
local lastClicked            -- item id of the last item we tried to disenchant
local dirty = true
local win, nextBtn, rows, statusText, countText, ignBtn = nil, nil, {}, nil, nil, nil
local checks = {}

local function DEName() return (GetSpellInfo and GetSpellInfo(DE_SPELL)) or "Disenchant" end
local function KnowsDE() return (IsPlayerSpell and IsPlayerSpell(DE_SPELL)) or (IsSpellKnown and IsSpellKnown(DE_SPELL)) end

-- current Enchanting skill (0 if not learned)
local function EnchantSkill()
  local want = (GetSpellInfo and GetSpellInfo(7411)) or "Enchanting"
  for i = 1, (GetNumSkillLines() or 0) do
    local name, header, _, rank = GetSkillLineInfo(i)
    if not header and (name == want or name == "Enchanting") then return rank or 0 end
  end
  return 0
end

-- Classic skill needed to disenchant, by item level (approximate above level 60 gear)
local function ReqSkill(ilvl, quality)
  ilvl = ilvl or 0
  if ilvl <= 20 then return 1 end
  if ilvl <= 60 then return math.min(200, 25 * math.ceil((ilvl - 20) / 5)) end
  if quality == 4 and ilvl >= 80 then return 300 end
  return 225
end

local function AHValue(link)
  if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemLink then
    local ok, v = pcall(Auctionator.API.v1.GetAuctionPriceByItemLink, "PintsDisenchant", link)
    if ok then return v end
  end
end

local function Money(c)
  if not c or c <= 0 then return "" end
  local g, s = math.floor(c / 10000), math.floor(c / 100) % 100
  if g > 0 then return ("|cffffd100%dg|r %ds"):format(g, s) end
  return ("|cffc7c7cf%ds|r"):format(s)
end

---------------------------------------------------------------- scanning
-- an item that has just been disenchanted stays in its bag slot for a moment (until its loot is taken), looking
-- perfectly normal. Aiming the next click at it gets "That item is not a valid target", so it's skipped until it's gone.
local doomed = {}           -- ["bag:slot"] = { id, t }
local function IsDoomed(bag, slot, id)
  local d = doomed[bag .. ":" .. slot]
  if not d then return false end
  if d.id ~= id or GetTime() - d.t > 6 then doomed[bag .. ":" .. slot] = nil; return false end
  return true
end
local function Scan()
  wipe(items); wipe(ignoredList)
  local skill = EnchantSkill()
  local seenIgnored = {}
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID and info.hyperlink and not IsDoomed(bag, slot, info.itemID) then
        local _, _, quality, ilvl, _, _, _, _, equipLoc, icon, _, classID, _, bindType = GetItemInfo(info.hyperlink)
        if quality and (classID == 2 or classID == 4) and quality >= 2 and quality <= 4
          and not (PintsDisenchantNoDE and PintsDisenchantNoDE[info.itemID])
          and equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_BODY" and equipLoc ~= "INVTYPE_TABARD" then
          local e = { bag = bag, slot = slot, id = info.itemID, link = info.hyperlink, quality = quality, ilvl = ilvl or 0,
                      icon = icon or info.iconFileID, bound = info.isBound, boe = (not info.isBound) and bindType == 2,
                      locked = info.isLocked, req = ReqSkill(ilvl, quality) }
          e.canDo = skill >= e.req
          if db.ignore[info.itemID] then
            if not seenIgnored[info.itemID] then seenIgnored[info.itemID] = true; ignoredList[#ignoredList + 1] = e end
          elseif db.q[quality] and (db.boe or not e.boe) and (db.sb or not e.bound) and not e.locked then
            items[#items + 1] = e
          end
        end
      end
    end
  end
  -- ignored items no longer in the bags still show (so they can be restored)
  for id in pairs(db.ignore) do
    if not seenIgnored[id] then
      local _, link, quality, ilvl, _, _, _, _, _, icon = GetItemInfo(id)
      ignoredList[#ignoredList + 1] = { id = id, link = link or ("item:" .. id), quality = quality or 1, ilvl = ilvl or 0, icon = icon, gone = true }
    end
  end
  local function order(a, b)
    if (a.canDo and true or false) ~= (b.canDo and true or false) then return a.canDo and true or false end
    if a.quality ~= b.quality then return a.quality < b.quality end
    if a.ilvl ~= b.ilvl then return a.ilvl < b.ilvl end
    return a.id < b.id
  end
  table.sort(items, order)
  table.sort(ignoredList, function(a, b) return a.id < b.id end)
  return skill
end

-- Arm a secure button to disenchant one bag slot. This casts the spell and targets the item in a single step -
-- unlike a "/cast + /use" macro, if the cast can't start (too soon, on cooldown) nothing else happens, so the item
-- is never equipped by mistake.
local function Arm(b, e)
  b:SetAttribute("macrotext1", nil)
  b:SetAttribute("type1", "spell"); b:SetAttribute("spell1", DEName())
  b:SetAttribute("target-bag", e.bag); b:SetAttribute("target-slot", e.slot)
end
local function Disarm(b)
  b:SetAttribute("type1", nil); b:SetAttribute("spell1", nil); b:SetAttribute("macrotext1", nil)
  b:SetAttribute("target-bag", nil); b:SetAttribute("target-slot", nil)
end

---------------------------------------------------------------- UI refresh (out of combat only)
local function FirstDoable()
  for _, e in ipairs(items) do if e.canDo then return e end end
end

local function Refresh()
  if not db then return end
  if InCombatLockdown() then dirty = true; return end
  dirty = false
  local skill = Scan()

  -- next button (kept current even with the window closed, so its keybind always points at the right bag slot)
  local nxt = FirstDoable()
  if nxt and KnowsDE() then
    Arm(nextBtn, nxt); nextBtn.item = nxt
  else
    Disarm(nextBtn); nextBtn.item = nil
  end
  if not win then return end
  local list = showIgnored and ignoredList or items
  if nxt and KnowsDE() then
    nextBtn.icon:SetTexture(nxt.icon); nextBtn.label:SetText("Disenchant next")
    nextBtn.sub:SetText(nxt.link or ""); nextBtn.icon:SetDesaturated(false)
  else
    nextBtn.icon:SetTexture("Interface\\Icons\\INV_Enchant_Disenchant"); nextBtn.icon:SetDesaturated(true)
    nextBtn.label:SetText(KnowsDE() and "Nothing to disenchant" or "Disenchant not learned")
    nextBtn.sub:SetText("")
  end

  -- rows
  local n = math.min(#list, ROWS_MAX)
  for i = 1, n do
    local e, r = list[i], rows[i]
    r.item = e
    r.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    local _, _, _, hex = GetItemQualityColor(e.quality or 1)
    local nm = (e.link and e.link:match("%[(.-)%]")) or ("Item " .. e.id)
    r.name:SetText(("|c%s%s|r"):format(hex or "ffffffff", nm))
    local tags = {}
    if e.boe then tags[#tags + 1] = "|cff66ccffBoE|r" end
    if e.gone then tags[#tags + 1] = "|cff808080not in bags|r" end
    if not showIgnored and not e.canDo then tags[#tags + 1] = ("|cffff4040needs %d|r"):format(e.req) end
    r.info:SetText(("ilvl %d  %s"):format(e.ilvl or 0, table.concat(tags, " ")))
    local v = (not showIgnored) and e.boe and AHValue(e.link)
    r.value:SetText(v and Money(v) or "")
    if not showIgnored and e.canDo and KnowsDE() then
      Arm(r, e)
      r.icon:SetDesaturated(false)
    else
      Disarm(r)
      r.icon:SetDesaturated(not showIgnored)
    end
    r:Show()
  end
  for i = n + 1, ROWS_MAX do rows[i]:Hide() end
  win.list:SetHeight(math.max(1, n * ROW_H))

  local doable = 0
  for _, e in ipairs(items) do if e.canDo then doable = doable + 1 end end
  if showIgnored then
    countText:SetText(("%d ignored item%s - click one to put it back on the list"):format(#ignoredList, #ignoredList == 1 and "" or "s"))
  else
    countText:SetText(("%d to disenchant  |cff909090(Enchanting %d)|r"):format(doable, skill))
  end
  ignBtn:SetText(showIgnored and "Back to list" or ("Ignored (" .. #ignoredList .. ")"))
  statusText:SetText(#list == 0 and (showIgnored and "Nothing ignored." or "Nothing in your bags matches the filters.") or "")
end

local function Ignore(e)
  if not e or not e.id then return end
  if InCombatLockdown() then return end
  if showIgnored then db.ignore[e.id] = nil else db.ignore[e.id] = true end
  Refresh()
end

---------------------------------------------------------------- secure button helpers
-- is the item a button points at still in that bag slot (and not mid-cast)? After a disenchant the dust or essence
-- often lands in the very slot the item left, so a button that hasn't caught up would target the wrong thing
local function SlotHolds(e)
  if type(e) ~= "table" or not (e.bag and e.slot) then return false end
  local info = C_Container.GetContainerItemInfo(e.bag, e.slot)
  return info ~= nil and info.itemID == e.id and not info.isLocked and not IsDoomed(e.bag, e.slot, e.id)
end

-- same, but ignoring the lock (an item stays locked for a moment after a failed cast)
local function SlotHas(e)
  if type(e) ~= "table" or not (e.bag and e.slot) then return false end
  local info = C_Container.GetContainerItemInfo(e.bag, e.slot)
  return info ~= nil and info.itemID == e.id
end

-- clicking while the last disenchant is still casting, its loot is still open, or the cursor is still in targeting
-- mode makes the game refuse the next item ("Item cannot be disenchanted") - or, worse, equip it. Skip that click.
local function Busy()
  if UnitCastingInfo and UnitCastingInfo("player") then return "casting" end
  if UnitChannelInfo and UnitChannelInfo("player") then return "channeling" end
  if LootFrame and LootFrame:IsShown() then return "loot open" end
end
-- a cursor left waiting for a target (from a click that didn't finish) would swallow the next disenchant: clear it
local function ClearTargeting()
  if SpellIsTargeting and SpellIsTargeting() and SpellStopTargeting then SpellStopTargeting() end
end
local clickedAt = 0
local function SkipClick(b, why)
  Disarm(b); lastClicked = nil
  UIErrorsFrame:AddMessage("Pint's Disenchant: wait for the last one to finish", 1, 0.82, 0)
  C_Timer.After(0.3, function() if not InCombatLockdown() then Refresh() end end)
end

local function MakeSecure(b)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("useOnKeyDown", false)       -- act once on release, for mouse and keybind alike
  b:SetAttribute("type2", nil)
end

-- the "next" button exists from load so its keybinding works even before the window is opened
nextBtn = CreateFrame("Button", "PintsDisenchantNext", UIParent, "SecureActionButtonTemplate, BackdropTemplate")
MakeSecure(nextBtn)
nextBtn:SetSize(W - 32, 48)
nextBtn:Hide()
nextBtn:SetScript("PreClick", function(self, button, down)
  if down then return end
  if not InCombatLockdown() then
    local why = Busy()
    if why then SkipClick(self, why); return end
    ClearTargeting(); clickedAt = GetTime()
    -- out of combat a click can still re-aim the button: check the slot first, rescan if it's changed
    if not SlotHolds(self.item) then Refresh() end
  end
  local it = self.item
  lastClicked = type(it) == "table" and { id = it.id, bag = it.bag, slot = it.slot } or nil
end)

---------------------------------------------------------------- window
local function Backdrop(f)
  f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
    tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
  f:SetBackdropColor(0.04, 0.04, 0.06, 0.95)
end

local function CreateWindow()
  win = CreateFrame("Frame", "PintsDisenchantFrame", UIParent, "BackdropTemplate")
  win:SetSize(W, H); win:SetFrameStrata("HIGH"); win:SetToplevel(true); win:SetClampedToScreen(true)
  local p = db.pos
  if p then win:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else win:SetPoint("CENTER", 300, 0) end
  Backdrop(win)
  win:EnableMouse(true); win:SetMovable(true); win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local a, _, b, x, y = self:GetPoint(); db.pos = { a, b, x, y }
  end)

  local logo = win:CreateTexture(nil, "ARTWORK"); logo:SetSize(30, 30); logo:SetPoint("TOPLEFT", 16, -14)
  logo:SetTexture("Interface\\Icons\\INV_Enchant_Disenchant"); logo:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 8, -1)
  title:SetText("Pint's Disenchant")
  countText = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); countText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
  local close = CreateFrame("Button", nil, win, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -4, -4)
  close:SetScript("OnClick", function()
    if InCombatLockdown() then UIErrorsFrame:AddMessage("Pint's Disenchant closes after combat.", 1, 0.3, 0.3); return end
    win:Hide()
  end)

  -- filters
  local defs = { { "q2", "Uncommon", 2 }, { "q3", "Rare", 3 }, { "q4", "Epic", 4 }, { "boe", "Bind on Equip" }, { "sb", "Soulbound" } }
  local x = 14
  for _, d in ipairs(defs) do
    local c = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate"); c:SetSize(22, 22); c:SetPoint("TOPLEFT", x, -50)
    c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); c.text:SetPoint("LEFT", c, "RIGHT", 1, 0)
    if d[3] then
      local _, _, _, hex = GetItemQualityColor(d[3]); c.text:SetText(("|c%s%s|r"):format(hex, d[2]))
      c:SetChecked(db.q[d[3]] and true or false)
      c:SetScript("OnClick", function(self) db.q[d[3]] = self:GetChecked() and true or nil; Refresh() end)
    else
      local key = d[1]
      c.text:SetText(d[2]); c:SetChecked(db[key] and true or false)
      c:SetScript("OnClick", function(self) db[key] = self:GetChecked() and true or false; Refresh() end)
      c:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(d[2])
        GameTooltip:AddLine(key == "boe"
          and "Include items that aren't soulbound yet. These can be sold - the list shows their auction value when Auctionator has one."
          or "Include items that are already soulbound to you (quest rewards, looted Bind on Pickup gear, and anything you've equipped).", 1, 1, 1, true)
        GameTooltip:Show()
      end)
      c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    checks[#checks + 1] = c
    x = x + 26 + c.text:GetStringWidth() + 8
  end

  -- list
  local sf = CreateFrame("ScrollFrame", "PintsDisenchantScroll", win, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 14, -78); sf:SetPoint("BOTTOMRIGHT", -34, 108)
  win.list = CreateFrame("Frame", nil, sf); win.list:SetSize(W - 50, 1); sf:SetScrollChild(win.list)
  local bg = win:CreateTexture(nil, "BACKGROUND", nil, 1); bg:SetPoint("TOPLEFT", sf, -2, 2); bg:SetPoint("BOTTOMRIGHT", sf, 24, -2)
  bg:SetColorTexture(0, 0, 0, 0.35)
  statusText = win:CreateFontString(nil, "OVERLAY", "GameFontDisable"); statusText:SetPoint("TOP", sf, "TOP", 10, -40)

  for i = 1, ROWS_MAX do
    local r = CreateFrame("Button", nil, win.list, "SecureActionButtonTemplate")
    MakeSecure(r)
    r:SetSize(W - 50, ROW_H - 1); r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    local stripe = r:CreateTexture(nil, "BACKGROUND"); stripe:SetAllPoints(); stripe:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0)
    r:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(22, 22); r.icon:SetPoint("LEFT", 2, 0)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r.name:SetPoint("TOPLEFT", 30, -1); r.name:SetWidth(250); r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.info = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); r.info:SetPoint("BOTTOMLEFT", 30, 1)
    r.value = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.value:SetPoint("RIGHT", -6, 0)
    r:SetScript("PreClick", function(self, button, down)
      if down or button ~= "LeftButton" or showIgnored or not self.item then return end
      if not InCombatLockdown() and Busy() then SkipClick(self); return end
      if not InCombatLockdown() then ClearTargeting(); clickedAt = GetTime() end
      if not InCombatLockdown() and not SlotHolds(self.item) then
        -- the list is out of date: skip this click and catch up
        Disarm(self); lastClicked = nil
        C_Timer.After(0, Refresh)
        return
      end
      lastClicked = { id = self.item.id, bag = self.item.bag, slot = self.item.slot }
    end)
    r:SetScript("PostClick", function(self, button, down)
      if down then return end
      if button == "RightButton" and not showIgnored then Ignore(self.item)
      elseif button == "LeftButton" and showIgnored then Ignore(self.item) end
    end)
    r:SetScript("OnEnter", function(self)
      if not self.item then return end
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      if self.item.bag then GameTooltip:SetBagItem(self.item.bag, self.item.slot) else GameTooltip:SetHyperlink("item:" .. self.item.id) end
      GameTooltip:AddLine(" ")
      if showIgnored then GameTooltip:AddLine("Click: put back on the disenchant list", 0.4, 1, 0.4)
      else
        if self.item.canDo then GameTooltip:AddLine("Left-click: disenchant", 0.4, 1, 0.4)
        else GameTooltip:AddLine(("Needs Enchanting %d"):format(self.item.req), 1, 0.25, 0.25) end
        GameTooltip:AddLine("Right-click: never disenchant this item", 1, 0.82, 0)
      end
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:Hide()
    rows[i] = r
  end

  -- next button
  nextBtn:SetParent(win); nextBtn:ClearAllPoints(); nextBtn:SetPoint("BOTTOM", 0, 48)
  nextBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  nextBtn:SetBackdropColor(0.22, 0.12, 0.35, 0.95); nextBtn:SetBackdropBorderColor(0.75, 0.5, 1, 0.9)
  nextBtn:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
  nextBtn.icon = nextBtn:CreateTexture(nil, "ARTWORK"); nextBtn.icon:SetSize(36, 36); nextBtn.icon:SetPoint("LEFT", 8, 0)
  nextBtn.label = nextBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); nextBtn.label:SetPoint("TOPLEFT", 52, -7)
  nextBtn.sub = nextBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); nextBtn.sub:SetPoint("BOTTOMLEFT", 52, 8)
  nextBtn.sub:SetWidth(W - 100); nextBtn.sub:SetJustifyH("LEFT"); nextBtn.sub:SetWordWrap(false)
  nextBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if self.item then GameTooltip:SetBagItem(self.item.bag, self.item.slot); GameTooltip:AddLine(" ") end
    GameTooltip:AddLine("Click once per item - the game needs a real click or key press for each cast.", 1, 1, 1, true)
    local key = GetBindingKey("CLICK PintsDisenchantNext:LeftButton")
    GameTooltip:AddLine(key and ("Keybind: " .. key) or "Tip: set a keybind under Key Bindings > AddOns > Pint's Disenchant.", 0.6, 0.8, 1, true)
    GameTooltip:Show()
  end)
  nextBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  nextBtn:Show()

  ignBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate"); ignBtn:SetSize(120, 22); ignBtn:SetPoint("BOTTOMLEFT", 16, 16)
  ignBtn:SetScript("OnClick", function() if InCombatLockdown() then return end; showIgnored = not showIgnored; Refresh() end)
  local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); hint:SetPoint("BOTTOMRIGHT", -18, 21)
  hint:SetText("Right-click an item to ignore it")

  win:SetScript("OnShow", function() Refresh() end)
  win:Hide()
end

local function Toggle()
  if InCombatLockdown() then print("|cffb48cffPint's Disenchant|r: can't open or close in combat."); return end
  if not win then CreateWindow() end
  if win:IsShown() then win:Hide() else showIgnored = false; win:Show() end
end
PintsDisenchant = { Toggle = Toggle, Refresh = Refresh }

SLASH_PINTSDISENCHANT1 = "/pd"
SLASH_PINTSDISENCHANT2 = "/disenchant"
SlashCmdList.PINTSDISENCHANT = function(msg)
  msg = (msg or ""):lower()
  if msg == "log" then
    print("|cffb48cffPint's Disenchant|r: last errors after a click" .. ((db.log and #db.log > 0) and ":" or " - none."))
    for i = 1, math.min(10, db.log and #db.log or 0) do print("  " .. db.log[i]) end
    return
  end
  if msg == "reset" then db.pos = nil; if win and not InCombatLockdown() then win:ClearAllPoints(); win:SetPoint("CENTER", 300, 0) end; return end
  Toggle()
end

---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
local pending
local function Soon()
  if pending then return end
  pending = true
  C_Timer.After(0.1, function() pending = nil; Refresh() end)
end

ev:SetScript("OnEvent", function(self, event, a1, a2, ...)
  if event == "ADDON_LOADED" then
    if a1 ~= ADDON then return end
    PintsDisenchantDB = PintsDisenchantDB or {}
    db = PintsDisenchantDB
    db.q = db.q or { [2] = true, [3] = true }
    if db.boe == nil then db.boe = true end
    if db.sb == nil then db.sb = true end
    db.ignore = db.ignore or {}
    db.minimap = db.minimap or {}
  elseif event == "PLAYER_LOGIN" then
    for _, e in ipairs({ "BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED", "GET_ITEM_INFO_RECEIVED", "PLAYER_REGEN_DISABLED",
                         "PLAYER_REGEN_ENABLED", "UI_ERROR_MESSAGE", "LEARNED_SPELL_IN_TAB", "UNIT_SPELLCAST_SUCCEEDED" }) do
      pcall(self.RegisterEvent, self, e)
    end
    C_Timer.After(2, Refresh)  -- arms the keybind even with the window closed
    -- minimap button
    local icon = "Interface\\Icons\\INV_Enchant_Disenchant"
    local function Tip(tt) tt:AddLine("Pint's Disenchant"); tt:AddLine("Click: open the disenchant list", 1, 1, 1) end
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    local Icon = LibStub and LibStub("LibDBIcon-1.0", true)
    if LDB and Icon then
      local obj = LDB:NewDataObject("PintsDisenchant", { type = "launcher", text = "Pint's Disenchant", icon = icon,
        OnClick = function() Toggle() end, OnTooltipShow = Tip })
      Icon:Register("PintsDisenchant", obj, db.minimap)
    else
      local b = CreateFrame("Button", "PintsDisenchantMinimapButton", Minimap)
      b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
      b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
      local ic = b:CreateTexture(nil, "BACKGROUND"); ic:SetTexture(icon); ic:SetSize(20, 20); ic:SetPoint("CENTER", 0, 1)
      local border = b:CreateTexture(nil, "OVERLAY"); border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); border:SetSize(53, 53); border:SetPoint("TOPLEFT")
      local store = db.minimap
      local function Place() local a = math.rad(store.angle or 225); b:ClearAllPoints(); b:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(a), 80 * math.sin(a)) end
      Place()
      b:RegisterForDrag("LeftButton")
      b:SetScript("OnDragStart", function() b:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter(); local px, py = GetCursorPosition(); local s = Minimap:GetEffectiveScale()
        store.angle = math.deg(math.atan2(py / s - my, px / s - mx)); Place() end) end)
      b:SetScript("OnDragStop", function() b:SetScript("OnUpdate", nil) end)
      b:SetScript("OnClick", function() Toggle() end)
      b:SetScript("OnEnter", function(s) GameTooltip:SetOwner(s, "ANCHOR_LEFT"); Tip(GameTooltip); GameTooltip:Show() end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
  elseif event == "PLAYER_REGEN_DISABLED" then
    -- still allowed to change secure buttons here (lockdown starts after this event). Disarm everything, because
    -- loot picked up in combat could land in a slot a button points at; re-armed after combat.
    Disarm(nextBtn); nextBtn.item = nil
    for _, r in ipairs(rows) do Disarm(r) end
    dirty = true
    if win and win:IsShown() then countText:SetText("|cffff4040In combat - paused|r") end
  elseif event == "PLAYER_REGEN_ENABLED" then
    Refresh()
  elseif event == "BAG_UPDATE_DELAYED" then
    Refresh()
  elseif event == "UI_ERROR_MESSAGE" then
    local msg = a2 or a1
    -- any red error right after one of our clicks: note it (/pd log) and don't leave the cursor stuck targeting
    if type(msg) == "string" and GetTime() - clickedAt < 3 then
      db.log = db.log or {}
      local it = lastClicked
      local info = it and C_Container.GetContainerItemInfo(it.bag, it.slot)
      table.insert(db.log, 1, ("%s  \"%s\"  item %s  in slot: %s  locked: %s  %s"):format(date("%m-%d %H:%M:%S"), msg, tostring(it and it.id),
        tostring(info ~= nil and it ~= nil and info.itemID == it.id), tostring(info and info.isLocked), Busy() or "idle"))
      while #db.log > 30 do table.remove(db.log) end
      C_Timer.After(0, ClearTargeting)
    end
    local cant = type(msg) == "string" and (msg == SPELL_FAILED_CANT_BE_DISENCHANTED
      or (msg:lower():find("disenchant", 1, true) and msg ~= SPELL_FAILED_CANT_BE_DISENCHANTED_SKILL and not msg:lower():find("skill", 1, true)))
    if lastClicked and cant then
      -- only give up on an item after it's refused twice in a row (once can just be bad timing)
      if SlotHas(lastClicked) then
        db.fails = db.fails or {}
        db.fails[lastClicked.id] = (db.fails[lastClicked.id] or 0) + 1
        if db.fails[lastClicked.id] >= 2 then
          db.ignore[lastClicked.id] = true; db.fails[lastClicked.id] = nil
          print("|cffb48cffPint's Disenchant|r: that item can't be disenchanted - moved it to Ignored.")
        end
      end
      lastClicked = nil
      Soon()
    end
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    -- a disenchant went through: that item clearly can be disenchanted
    if a1 == "player" and (...) == DE_SPELL and lastClicked then
      if db.fails then db.fails[lastClicked.id] = nil end
      doomed[lastClicked.bag .. ":" .. lastClicked.slot] = { id = lastClicked.id, t = GetTime() }
      lastClicked = nil
      Soon()                -- re-aim at the next item straight away
    end
  else
    if not InCombatLockdown() then Soon() else dirty = true end
  end
end)
