dofile("AuctionatorRemastered/Remastered/Core/Bootstrap.lua")
dofile("AuctionatorRemastered/Remastered/Models/BaitGuard.lua")

local checks = 0
local function check(v, msg)
	checks = checks + 1
	assert(v, msg or "assertion failed")
end

local BG = AuctionatorRemastered.Models.BaitGuard

-- =========================================================================
-- Test 1: Configuration & Defaults
-- =========================================================================
local function TestConfig()
	AUCTIONATOR_SAVEDVARS = {}
	check(BG.IsEnabled() == true, "BaitGuard should be enabled by default")
	check(BG.GetThreshold() == 40, "Default threshold should be 40%")

	AUCTIONATOR_SAVEDVARS.baitProtection = false
	check(BG.IsEnabled() == false, "BaitGuard should respect baitProtection = false")

	AUCTIONATOR_SAVEDVARS.baitProtection = true
	check(BG.IsEnabled() == true, "BaitGuard should respect baitProtection = true")

	AUCTIONATOR_SAVEDVARS.baitThreshold = 60
	check(BG.GetThreshold() == 60, "Configured threshold should be 60%")

	AUCTIONATOR_SAVEDVARS.baitThreshold = -10
	check(BG.GetThreshold() == 40, "Invalid negative threshold should fallback to 40%")

	AUCTIONATOR_SAVEDVARS.baitThreshold = 150
	check(BG.GetThreshold() == 40, "Threshold > 100 should fallback to 40%")

	AUCTIONATOR_SAVEDVARS = {}
end
TestConfig()

-- =========================================================================
-- Test 2: IsBaitPrice calculation
-- =========================================================================
local function TestIsBaitPrice()
	-- Market price: 100g (1,000,000 copper)
	local market = 1000000

	-- 1. Normal undercut: 95g (-5%) -> NOT bait
	local isBait, diff = BG.IsBaitPrice(950000, market)
	check(not isBait, "95g vs 100g should not be bait")
	check(math.floor(diff) == -5, "diff should be -5%")

	-- 2. Competitor matching: 100g (0%) -> NOT bait
	isBait, diff = BG.IsBaitPrice(1000000, market)
	check(not isBait, "100g vs 100g should not be bait")
	check(diff == 0, "diff should be 0%")

	-- 3. Overpriced: 150g (+50%) -> NOT bait
	isBait, diff = BG.IsBaitPrice(1500000, market)
	check(not isBait, "150g vs 100g should not be bait")
	check(diff == 50, "diff should be +50%")

	-- 4. Exactly at threshold: 60g (-40%) -> IS bait
	isBait, diff = BG.IsBaitPrice(600000, market, 40)
	check(isBait, "60g vs 100g with 40% threshold should be bait")
	check(math.floor(diff) == -40, "diff should be -40%")

	-- 5. Severe bait: 1 silver (100 copper) vs 100g -> IS bait (-99.99%)
	isBait, diff = BG.IsBaitPrice(100, market)
	check(isBait, "1s vs 100g should be bait")
	check(diff < -99, "diff should be < -99%")

	-- 6. Nil or zero checks
	check(BG.IsBaitPrice(nil, market) == false, "nil price should return false")
	check(BG.IsBaitPrice(1000, nil) == false, "nil market should return false")
	check(BG.IsBaitPrice(0, market) == false, "0 price should return false")
	check(BG.IsBaitPrice(1000, 0) == false, "0 market should return false")
	check(BG.IsBaitPrice(-10, market) == false, "negative price should return false")

	-- 7. Custom threshold: 25% threshold with 70g (-30%)
	isBait = BG.IsBaitPrice(700000, market, 25)
	check(isBait, "70g vs 100g with 25% threshold should be bait")
end
TestIsBaitPrice()

-- =========================================================================
-- Test 3: FindLowestNonBaitPrice
-- =========================================================================
local function TestFindLowestNonBait()
	local market = 500000 -- 50g

	-- Competitor list with bait at top
	local comps = {
		{ buyoutPrice = 100, stackSize = 1, owner = "Sniper1" }, -- 1 silver (Bait)
		{ buyoutPrice = 200, stackSize = 1, owner = "Sniper2" }, -- 2 silver (Bait)
		{ buyoutPrice = 480000, stackSize = 1, owner = "RealPlayer" }, -- 48 gold (Legit)
		{ buyoutPrice = 500000, stackSize = 1, owner = "OtherSeller" }, -- 50 gold (Legit)
	}

	local lowestPrice, entry, idx = BG.FindLowestNonBaitPrice(comps, market, 40)
	check(lowestPrice == 480000, "Lowest non-bait price should be 48g")
	check(entry.owner == "RealPlayer", "Lowest non-bait owner should be RealPlayer")
	check(idx == 3, "Lowest non-bait index should be 3")

	-- Stacks handling
	local stackComps = {
		{ buyoutPrice = 1000, stackSize = 20, owner = "Sniper" }, -- 50c per item (Bait)
		{ buyoutPrice = 9600000, stackSize = 20, owner = "BulkSeller" }, -- 48g per item (Legit)
	}
	lowestPrice, entry = BG.FindLowestNonBaitPrice(stackComps, market, 40)
	check(lowestPrice == 480000, "Lowest non-bait should calculate per-item buyout (48g)")
	check(entry.owner == "BulkSeller", "Entry should be BulkSeller")

	-- All competitors are bait
	local allBaitComps = {
		{ buyoutPrice = 100, stackSize = 1, owner = "Sniper1" },
		{ buyoutPrice = 500, stackSize = 1, owner = "Sniper2" },
	}
	lowestPrice, entry, idx = BG.FindLowestNonBaitPrice(allBaitComps, market, 40)
	check(lowestPrice == nil, "All bait list should return nil lowestPrice")
	check(entry == nil, "All bait list should return nil entry")
	check(idx == nil, "All bait list should return nil index")

	-- Empty or nil list
	check(BG.FindLowestNonBaitPrice({}, market) == nil, "Empty list should return nil")
	check(BG.FindLowestNonBaitPrice(nil, market) == nil, "Nil list should return nil")
end
TestFindLowestNonBait()

-- =========================================================================
-- Test 4: GetSmartUndercutPrice
-- =========================================================================
local function TestSmartUndercut()
	local market = 500000 -- 50 gold
	local vendor = 10000 -- 1 gold floor

	-- Scenario A: Sniper trap present at [1], legit seller at [2]
	local compsA = {
		{ buyoutPrice = 100, stackSize = 1, owner = "BaitSniper" }, -- 1 silver (Bait)
		{ buyoutPrice = 480000, stackSize = 1, owner = "NormalSeller" }, -- 48 gold (Legit)
	}
	local target, avoided, ref = BG.GetSmartUndercutPrice(compsA, market, vendor, 40)
	check(target == 479999, "Should undercut normal seller (48g - 1c = 47g 99s 99c)")
	check(avoided == true, "Bait price should be reported as avoided")
	check(ref == 480000, "Reference price should be 480,000")

	-- Scenario B: All listings are bait
	local compsB = {
		{ buyoutPrice = 50, stackSize = 1, owner = "BaitSniper1" },
		{ buyoutPrice = 100, stackSize = 1, owner = "BaitSniper2" },
	}
	target, avoided, ref = BG.GetSmartUndercutPrice(compsB, market, vendor, 40)
	check(target == 499999, "Should undercut market price when all listings are bait (50g - 1c)")
	check(avoided == true, "Bait price should be avoided")
	check(ref == 500000, "Reference price used should be market (500,000)")

	-- Scenario C: No bait, healthy competition
	local compsC = {
		{ buyoutPrice = 490000, stackSize = 1, owner = "HealthySeller" },
		{ buyoutPrice = 500000, stackSize = 1, owner = "OtherSeller" },
	}
	target, avoided, ref = BG.GetSmartUndercutPrice(compsC, market, vendor, 40)
	check(target == 489999, "Should undercut lowest healthy competitor (49g - 1c)")
	check(avoided == false, "No bait avoided")
	check(ref == 490000, "Reference price used should be 490,000")

	-- Scenario D: No competitors at all
	target, avoided = BG.GetSmartUndercutPrice({}, market, vendor, 40)
	check(target == 499999, "Empty comps should undercut market (50g - 1c)")
	check(avoided == false, "No bait avoided")

	-- Scenario E: No competitors, no market data (fallback to vendor price)
	target, avoided = BG.GetSmartUndercutPrice({}, 0, vendor, 40)
	check(target == vendor, "Fallback to vendor price when no market data")
	check(avoided == false, "No bait avoided")
end
TestSmartUndercut()

-- =========================================================================
-- Test 5: AnalyzeCompetitors
-- =========================================================================
local function TestAnalyzeCompetitors()
	local market = 100000 -- 10g
	local comps = {
		{ buyoutPrice = 100, stackSize = 1 }, -- 1s (-99%)
		{ buyoutPrice = 20000, stackSize = 1 }, -- 2g (-80%)
		{ buyoutPrice = 90000, stackSize = 1 }, -- 9g (-10%)
		{ buyoutPrice = 105000, stackSize = 1 }, -- 10.5g (+5%)
	}

	local summary = BG.AnalyzeCompetitors(comps, market, 40)
	check(summary.hasBait == true, "Summary should flag hasBait")
	check(summary.baitCount == 2, "Summary should count 2 bait auctions")
	check(summary.lowestBait == 100, "Lowest bait should be 100 copper")
	check(summary.lowestNormal == 90000, "Lowest normal should be 90,000 copper")
	check(math.floor(summary.maxDiscountPct) == 99, "Max discount should be 99%")
end
TestAnalyzeCompetitors()

-- =========================================================================
-- Test 6: Global Aliases
-- =========================================================================
local function TestGlobalAliases()
	check(type(_G.Atr_CheckBaitPrice) == "function", "Atr_CheckBaitPrice global should be defined")
	check(type(_G.Atr_GetSmartUndercutPrice) == "function", "Atr_GetSmartUndercutPrice global should be defined")
	check(type(_G.Atr_FindLowestNonBaitPrice) == "function", "Atr_FindLowestNonBaitPrice global should be defined")

	local isBait = _G.Atr_CheckBaitPrice(100, 100000)
	check(isBait == true, "Global alias Atr_CheckBaitPrice should work")
end
TestGlobalAliases()

print(string.format("PASS: %d checks passed in test_bait_guard.lua", checks))
