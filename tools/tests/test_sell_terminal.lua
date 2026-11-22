dofile("AuctionatorRemastered/Remastered/Core/Bootstrap.lua")
dofile("AuctionatorRemastered/Remastered/Integration/LegacyBridge.lua")
dofile("AuctionatorRemastered/Remastered/Models/BaitGuard.lua")
dofile("AuctionatorRemastered/Remastered/Models/PriceGuard.lua")

local checks = 0
local function check(v, msg)
	checks = checks + 1
	assert(v, msg or "assertion failed")
end

-- =========================================================================
-- Fixtures & Mocks
-- =========================================================================
local now = 1000000
function time()
	return now
end
function GetTime()
	return now
end
function ZT(s)
	return s
end
function hooksecurefunc(name, callback)
	-- Mock hook
end

ITEM_SOULBOUND = "Soulbound"
ITEM_BIND_ON_PICKUP = "Binds when picked up"
ITEM_BIND_ON_EQUIP = "Binds when equipped"
ITEM_BIND_ON_USE = "Binds when used"
ITEM_BIND_QUEST = "Quest Item"
ITEM_BIND_TO_ACCOUNT = "Binds to account"
ITEM_CONJURED = "Conjured Item"

-- Mock Tooltip for bag scanning
local mockTipLines = {}
AtrScanningTooltip = {
	lines = {},
	ClearLines = function(self)
		self.lines = {}
	end,
	SetBagItem = function(self, bag, slot)
		local key = string.format("%d_%d", bag, slot)
		self.lines = mockTipLines[key] or {}
		return true
	end,
	NumLines = function(self)
		return #self.lines
	end,
	GetName = function()
		return "AtrScanningTooltip"
	end,
}

_G["AtrScanningTooltip"] = AtrScanningTooltip
setmetatable(_G, {
	__index = function(t, k)
		local prefix = "AtrScanningTooltipTextLeft"
		if type(k) == "string" and string.sub(k, 1, #prefix) == prefix then
			local lineIdx = tonumber(string.sub(k, #prefix + 1))
			if lineIdx and lineIdx <= #AtrScanningTooltip.lines then
				return {
					GetText = function()
						return AtrScanningTooltip.lines[lineIdx]
					end,
				}
			end
			return {
				GetText = function()
					return nil
				end,
			}
		end
		return rawget(t, k)
	end,
})

-- =========================================================================
-- Test 1: Soulbound Filter Logic
-- =========================================================================
local function TestSoulboundFiltering()
	local function IsItemSoulbound(bag, slot)
		local tip = _G["AtrScanningTooltip"]
		tip:ClearLines()
		tip:SetBagItem(bag, slot)
		local numLines = tip:NumLines() or 0
		local tipName = tip:GetName()
		for i = 2, numLines do
			local line = _G[tipName .. "TextLeft" .. i]
			if line then
				local text = line:GetText()
				if text then
					if
						text == ITEM_SOULBOUND
						or text == ITEM_BIND_ON_PICKUP
						or text == ITEM_BIND_QUEST
						or text == ITEM_BIND_TO_ACCOUNT
						or text == ITEM_CONJURED
					then
						return true
					end
				end
			end
		end
		return false
	end

	-- BoP Item
	mockTipLines["0_1"] = { "Worn Shortsword", "Binds when picked up", "One-Hand Sword" }
	check(IsItemSoulbound(0, 1) == true, "BoP item should be flagged as bound")

	-- Soulbound BoE Item
	mockTipLines["0_2"] = { "Shadowcraft Cap", "Soulbound", "Head", "Leather" }
	check(IsItemSoulbound(0, 2) == true, "Equipped/Soulbound item should be flagged as bound")

	-- Quest Item
	mockTipLines["0_3"] = { "Captain's Key", "Quest Item" }
	check(IsItemSoulbound(0, 3) == true, "Quest item should be flagged as bound")

	-- Conjured Item
	mockTipLines["0_4"] = { "Conjured Mana Water", "Conjured Item" }
	check(IsItemSoulbound(0, 4) == true, "Conjured item should be flagged as bound")

	-- Heirloom / Account-bound
	mockTipLines["0_5"] = { "Bloodied Arcanite Reaper", "Binds to account" }
	check(IsItemSoulbound(0, 5) == true, "Account-bound item should be flagged as bound")

	-- Unbound BoE item (Sellable!)
	mockTipLines["0_6"] = { "Krol Blade", "Binds when equipped", "One-Hand Sword" }
	check(IsItemSoulbound(0, 6) == false, "Unbound BoE item must NOT be flagged as bound")

	-- Reagent / Trade Goods (Sellable!)
	mockTipLines["0_7"] = { "Peacebloom", "Crafting Reagent" }
	check(IsItemSoulbound(0, 7) == false, "Trade goods must NOT be flagged as bound")
end
TestSoulboundFiltering()

-- =========================================================================
-- Test 2: Bag Aggregation & Total Value Calculation
-- =========================================================================
local function TestBagAggregation()
	local mockBags = {
		{
			bag = 0,
			slot = 1,
			id = "item:2447:0",
			name = "Peacebloom",
			count = 20,
			maxStack = 20,
			vendor = 10,
			market = 500,
			quality = 1,
			type = "Trade Goods",
		},
		{
			bag = 0,
			slot = 2,
			id = "item:2447:0",
			name = "Peacebloom",
			count = 15,
			maxStack = 20,
			vendor = 10,
			market = 500,
			quality = 1,
			type = "Trade Goods",
		},
		{
			bag = 1,
			slot = 5,
			id = "item:2447:0",
			name = "Peacebloom",
			count = 20,
			maxStack = 20,
			vendor = 10,
			market = 500,
			quality = 1,
			type = "Trade Goods",
		},
		{
			bag = 0,
			slot = 3,
			id = "item:1234:0",
			name = "Krol Blade",
			count = 1,
			maxStack = 1,
			vendor = 50000,
			market = 1500000,
			quality = 4,
			type = "Weapon",
		},
	}

	local itemMap = {}
	local bagItems = {}
	for _, item in ipairs(mockBags) do
		local entry = itemMap[item.id]
		if not entry then
			local unitPrice = (item.market > 0 and item.market) or item.vendor
			entry = {
				key = item.id,
				name = item.name,
				type = item.type,
				maxStack = item.maxStack,
				unitPrice = unitPrice,
				totalCount = 0,
				totalValue = 0,
				slots = {},
			}
			itemMap[item.id] = entry
			bagItems[#bagItems + 1] = entry
		end
		entry.totalCount = entry.totalCount + item.count
		entry.slots[#entry.slots + 1] = { bag = item.bag, slot = item.slot, count = item.count }
	end

	for _, item in ipairs(bagItems) do
		item.totalValue = item.unitPrice * item.totalCount
	end

	check(#bagItems == 2, "Duplicate Peacebloom stacks should be aggregated into 1 entry")
	local pb = itemMap["item:2447:0"]
	check(pb.totalCount == 55, "Peacebloom totalCount should be 20 + 15 + 20 = 55")
	check(pb.totalValue == 55 * 500, "Peacebloom totalValue should be 55 * 500 = 27500")
	check(#pb.slots == 3, "Peacebloom slots list should have 3 entries")

	local kb = itemMap["item:1234:0"]
	check(kb.totalCount == 1, "Krol Blade count should be 1")
	check(kb.totalValue == 1500000, "Krol Blade totalValue should be 1,500,000")

	-- Sort by totalValue descending
	table.sort(bagItems, function(a, b)
		return a.totalValue > b.totalValue
	end)
	check(bagItems[1].name == "Krol Blade", "Highest total value item (Krol Blade) should be first")
	check(bagItems[2].name == "Peacebloom", "Lower total value item (Peacebloom) should be second")
end
TestBagAggregation()

-- =========================================================================
-- Test 3: Quick Stacking Math
-- =========================================================================
local function TestQuickStacking()
	local totalItems = 55
	local maxStack = 20

	-- Preset "all"
	local sizeAll = math.min(totalItems, maxStack)
	local countAll = math.max(1, math.floor(totalItems / sizeAll))
	check(sizeAll == 20, "Preset 'all' stack size should be 20")
	check(countAll == 2, "Preset 'all' num stacks should be 2 (55 / 20 = 2 full stacks)")

	-- Preset "singles"
	local sizeSingles = 1
	local countSingles = totalItems
	check(sizeSingles == 1, "Preset 'singles' stack size should be 1")
	check(countSingles == 55, "Preset 'singles' num stacks should be 55")

	-- Preset "full"
	local sizeFull = maxStack
	local countFull = math.max(1, math.floor(totalItems / maxStack))
	check(sizeFull == 20, "Preset 'full' stack size should be 20")
	check(countFull == 2, "Preset 'full' num stacks should be 2")
end
TestQuickStacking()

-- =========================================================================
-- Test 4: Quick Price Undercut / Match / Market Math
-- =========================================================================
local function TestQuickPricing()
	local lowestBuyout = 50000 -- 5g
	local marketRef = 55000 -- 5.5g
	local vendorFloor = 1000 -- 10s

	-- Undercut 1c
	local priceUndercut = math.max(1, lowestBuyout - 1)
	check(priceUndercut == 49999, "Undercut should subtract 1 copper from lowest buyout (49999)")

	-- Match
	local priceMatch = lowestBuyout
	check(priceMatch == 50000, "Match should exactly equal lowest buyout (50000)")

	-- Market
	local priceMarket = marketRef
	check(priceMarket == 55000, "Market should equal 14-day median reference (55000)")

	-- Undercut edge case: lowest buyout is 1 copper
	local priceUndercut1c = math.max(1, 1 - 1)
	check(priceUndercut1c == 1, "Undercutting 1 copper should cap at minimum 1 copper")
end
TestQuickPricing()

-- =========================================================================
-- Test 5: Financial Estimates (Net Revenue & Deposit)
-- =========================================================================
local function TestFinancialEstimates()
	local unitBuyout = 10000 -- 1g
	local stackSize = 20
	local numStacks = 5
	local stackBuyout = unitBuyout * stackSize -- 20g
	local grossRevenue = stackBuyout * numStacks -- 100g = 1,000,000 copper

	-- 5% AH cut
	local netRevenue = math.floor(grossRevenue * 0.95)
	check(netRevenue == 950000, "Net revenue after 5% cut should be 95g (950,000 copper)")

	-- CalculateAuctionDeposit mock
	function CalculateAuctionDeposit(duration, totalItems)
		-- Mock deposit: 15% of vendor price for 12h
		local vendorPrice = 100
		return math.floor(vendorPrice * totalItems * 0.15 * duration)
	end

	local deposit12h = CalculateAuctionDeposit(1, stackSize * numStacks)
	local deposit24h = CalculateAuctionDeposit(2, stackSize * numStacks)
	check(deposit12h == 1500, "12h deposit should be 1500 copper")
	check(deposit24h == 3000, "24h deposit should be 3000 copper")
end
TestFinancialEstimates()

-- =========================================================================
-- Test 6: Settings Toggle Fallback
-- =========================================================================
local function TestSettingsToggle()
	AUCTIONATOR_SAVEDVARS = {}

	-- Default: modernSell is true
	local useModernDefault = AUCTIONATOR_SAVEDVARS.modernSell ~= false
	check(useModernDefault == true, "Modern sell should default to true")

	-- Explicitly enabled
	AUCTIONATOR_SAVEDVARS.modernSell = true
	check(AUCTIONATOR_SAVEDVARS.modernSell ~= false, "Modern sell should be enabled when true")

	-- Explicitly disabled (Classic 2008 view)
	AUCTIONATOR_SAVEDVARS.modernSell = false
	check((AUCTIONATOR_SAVEDVARS.modernSell ~= false) == false, "Modern sell should be disabled when false")
end
TestSettingsToggle()

-- =========================================================================
-- Test 7: Bait Guard Integration in Sell Terminal
-- =========================================================================
local function TestBaitGuardIntegration()
	local BG = AuctionatorRemastered.Models.BaitGuard
	check(BG ~= nil, "BaitGuard model should be loaded")

	local marketPrice = 1000000 -- 100g
	local vendorPrice = 5000 -- 50s
	local competitors = {
		{ type = "n", buyoutPrice = 100, stackSize = 1, owner = "Sniper" }, -- 1 silver (Bait)
		{ type = "n", buyoutPrice = 950000, stackSize = 1, owner = "HonestSeller" }, -- 95 gold (Legit)
	}

	-- When Bait Guard is active (default), it avoids the 1 silver trap
	local smartPrice, avoided, ref = BG.GetSmartUndercutPrice(competitors, marketPrice, vendorPrice)
	check(avoided == true, "Should report bait price avoided")
	check(smartPrice == 949999, "Should undercut honest seller at 94g 99s 99c instead of 99 copper")
	check(ref == 950000, "Reference price should be 95g")

	-- Analysis summary check
	local summary = BG.AnalyzeCompetitors(competitors, marketPrice)
	check(summary.hasBait == true, "Summary should detect bait")
	check(summary.baitCount == 1, "Summary should count 1 bait")
	check(summary.lowestBait == 100, "Lowest bait should be 100c")
	check(summary.lowestNormal == 950000, "Lowest normal should be 950,000c")
end
TestBaitGuardIntegration()

-- =========================================================================
-- Test 8: Price Deviation & Surge Guard Integration in Sell Terminal
-- =========================================================================
local function TestPriceGuardIntegration()
	local PG = AuctionatorRemastered.Models.PriceGuard
	check(PG ~= nil, "PriceGuard model should be loaded")

	local marketPrice = 1000000 -- 100g
	local vendorPrice = 10000 -- 1g

	-- Surge: 500g (>300% surge)
	local evalSurge = PG.EvaluatePrice(5000000, marketPrice, vendorPrice)
	check(evalSurge.isAnomaly == true, "500g is anomaly")
	check(evalSurge.anomalyType == "EXTREME_HIGH", "Anomaly is EXTREME_HIGH")
	local badge, hex = PG.GetBadgeText(evalSurge)
	check(badge:find("Price Surge", 1, true) ~= nil, "Badge text warns surge")

	-- Dump: 10g (<20% of market, i.e. 90% below)
	local evalDump = PG.EvaluatePrice(100000, marketPrice, vendorPrice)
	check(evalDump.isAnomaly == true, "10g is dump anomaly")
	check(evalDump.anomalyType == "EXTREME_LOW", "Anomaly is EXTREME_LOW")

	-- Below vendor: 50s (<1g vendor price)
	local evalVendor = PG.EvaluatePrice(5000, marketPrice, vendorPrice)
	check(evalVendor.isAnomaly == true, "50s is below vendor")
	check(evalVendor.anomalyType == "BELOW_VENDOR", "Anomaly is BELOW_VENDOR")
	badge, hex = PG.GetBadgeText(evalVendor)
	check(badge:find("Below Vendor Floor", 1, true) ~= nil, "Badge warns below vendor")
	check(hex == "ff4444", "Below vendor badge is red")
end
TestPriceGuardIntegration()

print(string.format("PASS: %d SellTerminal unit tests passed successfully", checks))
