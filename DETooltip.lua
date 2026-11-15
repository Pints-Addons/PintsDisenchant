-- Pint's Disenchant: what an item disenchants into, in its tooltip - each possible material, how many and the odds,
-- the Enchanting skill it needs, and roughly what that's worth (Pint's Auctions' prices, when it's loaded).
-- Odds: on WoW Forever, Forever's own (Wowhead's WoW Forever database); on Classic Era, Classic's disenchant tables
-- (by item level, quality, and armour or weapon).
local GII = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- materials: id = English name (shown until the game has the item's own name)
local NAME = {
	[10940] = "Strange Dust", [11083] = "Soul Dust", [11137] = "Vision Dust", [11176] = "Dream Dust", [16204] = "Illusion Dust",
	[10938] = "Lesser Magic Essence", [10939] = "Greater Magic Essence", [10998] = "Lesser Astral Essence", [11082] = "Greater Astral Essence",
	[11134] = "Lesser Mystic Essence", [11135] = "Greater Mystic Essence", [11174] = "Lesser Nether Essence", [11175] = "Greater Nether Essence",
	[16202] = "Lesser Eternal Essence", [16203] = "Greater Eternal Essence",
	[10978] = "Small Glimmering Shard", [11084] = "Large Glimmering Shard", [11138] = "Small Glowing Shard", [11139] = "Large Glowing Shard",
	[11177] = "Small Radiant Shard", [11178] = "Large Radiant Shard", [14343] = "Small Brilliant Shard", [14344] = "Large Brilliant Shard",
	[20725] = "Nexus Crystal",
}
-- uncommon (green): up to item level -> { dust, min, max }, { essence, min, max }, { shard }
local GREEN = {
	{ 15, { 10940, 1, 2 }, { 10938, 1, 2 }, nil },
	{ 20, { 10940, 2, 3 }, { 10939, 1, 2 }, { 10978, 1, 1 } },
	{ 25, { 10940, 4, 6 }, { 10998, 1, 2 }, { 10978, 1, 1 } },
	{ 30, { 11083, 1, 2 }, { 11082, 1, 2 }, { 11084, 1, 1 } },
	{ 35, { 11083, 2, 5 }, { 11134, 1, 2 }, { 11138, 1, 1 } },
	{ 40, { 11137, 1, 2 }, { 11135, 1, 2 }, { 11139, 1, 1 } },
	{ 45, { 11137, 2, 5 }, { 11174, 1, 2 }, { 11177, 1, 1 } },
	{ 50, { 11176, 1, 2 }, { 11175, 1, 2 }, { 11178, 1, 1 } },
	{ 55, { 11176, 2, 5 }, { 16202, 1, 2 }, { 14343, 1, 1 } },
	{ 60, { 16204, 1, 2 }, { 16203, 1, 2 }, { 14344, 1, 1 } },
	{ 999, { 16204, 2, 5 }, { 16203, 2, 3 }, { 14344, 1, 1 } },
}
-- rare (blue): up to item level -> shard
local BLUE = { { 25, 10978 }, { 30, 11084 }, { 35, 11138 }, { 40, 11139 }, { 45, 11177 }, { 50, 11178 }, { 55, 14343 }, { 999, 14344 } }
-- epic (purple): up to item level -> { material, min, max }
local PURPLE = { { 45, { 11177, 2, 4 } }, { 50, { 11178, 2, 4 } }, { 55, { 14344, 2, 4 } }, { 60, { 20725, 1, 1 } }, { 999, { 20725, 1, 2 } } }

-- WoW Forever's own disenchant odds (Wowhead's WoW Forever database, November 15, 2026 - what thousands of disenchants
-- turned up): FOREVER[quality][weapon and 2 or 4] = { { up to item level, { odds %, material, min, max }, ... }, ... }
local FOREVER = {
	[2] = {
		[2] = {
			{ 15, { 100, 10938, 1, 2 } },
			{ 20, { 93, 10939, 1, 2 }, { 7, 10940, 1, 3 } },
			{ 25, { 88, 10939, 1, 2 }, { 7, 10978, 1, 1 }, { 5, 10940, 2, 6 } },
			{ 30, { 87, 10939, 1, 3 }, { 7, 11083, 1, 2 }, { 6, 11084, 1, 1 } },
			{ 35, { 74, 11134, 1, 2 }, { 14, 11138, 1, 1 }, { 12, 11083, 2, 5 } },
			{ 40, { 90, 11135, 1, 2 }, { 10, 11139, 1, 1 } },
			{ 45, { 90, 11174, 1, 2 }, { 10, 11137, 2, 5 } },
			{ 50, { 95, 11175, 1, 2 }, { 5, 11178, 1, 1 } },
			{ 55, { 100, 16202, 1, 2 } },
			{ 60, { 86, 16203, 1, 2 }, { 14, 16204, 1, 2 } },
			{ 999, { 100, 16203, 2, 3 } },
		},
		[4] = {
			{ 15, { 78, 10940, 1, 2 }, { 22, 10938, 1, 2 } },
			{ 20, { 91, 10940, 2, 3 }, { 9, 10939, 1, 2 } },
			{ 25, { 42, 10998, 1, 3 }, { 41, 10940, 2, 6 }, { 18, 10978, 1, 1 } },
			{ 30, { 72, 11083, 1, 3 }, { 21, 11082, 1, 3 }, { 8, 11084, 1, 1 } },
			{ 35, { 69, 11083, 1, 5 }, { 23, 11134, 1, 2 }, { 8, 11138, 1, 1 } },
			{ 40, { 51, 11135, 1, 3 }, { 38, 11137, 1, 3 }, { 11, 11139, 1, 1 } },
			{ 45, { 74, 11137, 2, 5 }, { 21, 11174, 1, 3 }, { 4, 11177, 1, 1 } },
			{ 50, { 60, 11176, 1, 2 }, { 34, 11175, 1, 2 }, { 6, 11178, 1, 1 } },
			{ 55, { 69, 11176, 2, 5 }, { 31, 16202, 1, 2 } },
			{ 60, { 79, 16204, 1, 2 }, { 21, 16203, 1, 2 } },
			{ 999, { 83, 16204, 2, 5 }, { 17, 16203, 2, 3 } },
		},
	},
	[3] = {
		[2] = {
			{ 25, { 62, 10978, 1, 1 }, { 38, 10939, 1, 3 } },
			{ 30, { 70, 11084, 1, 1 }, { 30, 11083, 1, 2 } },
			{ 35, { 100, 11138, 1, 1 } },
			{ 40, { 100, 11139, 1, 1 } },
			{ 45, { 89, 11177, 1, 1 }, { 6, 11139, 1, 1 }, { 5, 11174, 1, 2 } },
			{ 50, { 93, 11178, 1, 1 }, { 7, 11175, 1, 2 } },
			{ 55, { 97, 14343, 1, 1 }, { 3, 16202, 1, 2 } },
			{ 60, { 92, 14344, 1, 1 }, { 8, 16203, 1, 2 } },
			{ 999, { 100, 14344, 1, 1 } },
		},
		[4] = {
			{ 25, { 86, 10978, 1, 1 }, { 14, 10940, 2, 3 } },
			{ 30, { 100, 11084, 1, 1 } },
			{ 35, { 83, 11138, 1, 1 }, { 11, 11134, 1, 2 }, { 6, 11083, 2, 5 } },
			{ 40, { 86, 11139, 1, 1 }, { 14, 11137, 1, 2 } },
			{ 45, { 93, 11177, 1, 1 }, { 7, 11137, 1, 5 } },
			{ 50, { 100, 11178, 1, 1 } },
			{ 55, { 100, 14343, 1, 1 } },
			{ 60, { 100, 14344, 1, 1 } },
			{ 999, { 100, 14344, 1, 1 } },
		},
	},
	[4] = {
		[2] = {
			{ 45, { 100, 11177, 2, 4 } },
			{ 60, { 100, 20725, 1, 1 } },
			{ 999, { 100, 20725, 1, 2 } },
		},
		[4] = {
			{ 45, { 100, 11177, 2, 4 } },
			{ 50, { 100, 11178, 2, 4 } },
			{ 60, { 100, 20725, 1, 1 } },
			{ 999, { 100, 20725, 1, 2 } },
		},
	},
}
local function Pick(t, ilvl) for _, r in ipairs(t) do if ilvl <= r[1] then return r end end end
-- { { odds %, id, min, max }, ... }
local function Results(quality, ilvl, isWeapon)
	local out = {}
	if type(issecretvalue) == "function" then
		local t = FOREVER[quality] and FOREVER[quality][isWeapon and 2 or 4]
		local r = t and Pick(t, ilvl)
		if r then for i = 2, #r do out[#out + 1] = { r[i][1], r[i][2], r[i][3], r[i][4] } end; return out end
	end
	if quality == 2 then
		local r = Pick(GREEN, ilvl)
		local dust, ess = isWeapon and 20 or 75, isWeapon and 75 or 20
		if not r[4] then dust, ess = isWeapon and 20 or 80, isWeapon and 80 or 20 end
		out[#out + 1] = { dust, r[2][1], r[2][2], r[2][3] }
		out[#out + 1] = { ess, r[3][1], r[3][2], r[3][3] }
		if r[4] then out[#out + 1] = { 5, r[4][1], 1, 1 } end
		table.sort(out, function(a, b) return a[1] > b[1] end)
	elseif quality == 3 then
		local r = Pick(BLUE, ilvl)
		if ilvl > 55 then out[1] = { 99.5, r[2], 1, 1 }; out[2] = { 0.5, 20725, 1, 1 }
		else out[1] = { 100, r[2], 1, 1 } end
	elseif quality == 4 then
		local r = Pick(PURPLE, ilvl)
		out[1] = { 100, r[2][1], r[2][2], r[2][3] }
	end
	return out
end
-- Enchanting skill to disenchant it (Classic)
local function ReqSkill(ilvl, quality)
	if ilvl <= 20 then return 1 end
	if ilvl <= 60 then return math.min(200, 25 * math.ceil((ilvl - 20) / 5)) end
	if quality == 4 and ilvl >= 80 then return 300 end
	return 225
end
local function Skill()
	if GetProfessions and GetProfessionInfo then
		for _, p in ipairs({ GetProfessions() }) do
			if p then local _, _, rank, _, _, _, line = GetProfessionInfo(p); if line == 333 then return rank end end
		end
	end
	if GetNumSkillLines and GetSkillLineInfo then
		for i = 1, GetNumSkillLines() do
			local name, header, _, rank = GetSkillLineInfo(i)
			if not header and name == "Enchanting" then return rank end
		end
	end
end
local function Price(id)
	local PA = _G.PintsAuctions
	if PA and PA.Price then local ok, v = pcall(PA.Price, id); if ok and type(v) == "number" and v > 0 then return v end end
end
local function Money(c)
	c = math.floor(c + 0.5)
	local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
	if g > 0 then return ("%d|cffffd700g|r %d|cffc7c7cfs|r"):format(g, s) end
	if s > 0 then return ("%d|cffc7c7cfs|r %d|cffeda55fc|r"):format(s, cp) end
	return cp .. "|cffeda55fc|r"
end

local function Add(tt, link)
	if not link or (issecretvalue and issecretvalue(link)) or type(link) ~= "string" then return end
	if PintsDisenchantDB and PintsDisenchantDB.deTooltip == false then return end
	local id = tonumber(link:match("item:(%d+)"))
	if not id or (PintsDisenchantNoDE and PintsDisenchantNoDE[id]) then return end
	local _, _, quality, ilvl, _, _, _, _, equipLoc, _, _, classID = GII(link)
	if not (quality and quality >= 2 and quality <= 4 and (classID == 2 or classID == 4)) then return end
	if not equipLoc or equipLoc == "" or equipLoc == "INVTYPE_BODY" or equipLoc == "INVTYPE_TABARD" then return end
	ilvl = ilvl or 0
	local res = Results(quality, ilvl, classID == 2)
	if #res == 0 then return end
	local req, have = ReqSkill(ilvl, quality), Skill()
	tt:AddLine(" ")
	local need = (have and have < req) and ("  |cffff4040needs Enchanting " .. req .. "|r") or ("  |cff888888Enchanting " .. req .. "|r")
	tt:AddLine("Disenchants into:" .. need, 0.6, 0.4, 1)
	local worth, priced = 0, true
	for _, r in ipairs(res) do
		local name = GII(r[2]) or NAME[r[2]] or ("item " .. r[2])
		local n = (r[3] == r[4]) and (r[3] > 1 and (" x" .. r[3]) or "") or (" x" .. r[3] .. "-" .. r[4])
		local odds = (r[1] % 1 == 0) and (r[1] .. "%") or (r[1] .. "%")
		local p = Price(r[2])
		if p then worth = worth + p * (r[3] + r[4]) / 2 * r[1] / 100 else priced = false end
		tt:AddDoubleLine("  " .. odds .. "  " .. name .. n, p and Money(p) .. " each" or "", 1, 1, 1, 0.8, 0.8, 0.8)
	end
	if worth > 0 then tt:AddDoubleLine("  Worth about", Money(worth) .. (priced and "" or " +"), 0.6, 0.4, 1, 1, 1, 1) end
	tt:Show()
end

-- every item tooltip: the modern client's tooltip data hook (WoW Forever), else the classic item hook
if TooltipDataProcessor and Enum and Enum.TooltipDataType then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt)
		if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
		local ok, _, link = pcall(tt.GetItem, tt)
		if ok then Add(tt, link) end
	end)
else
	for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
		tt:HookScript("OnTooltipSetItem", function(self) local _, link = self:GetItem(); Add(self, link) end)
	end
end
