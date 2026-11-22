dofile("AuctionatorRemastered/Remastered/Core/Bootstrap.lua")
dofile("AuctionatorRemastered/Remastered/Models/SearchModifiers.lua")

local checks = 0
local function check(v, msg)
    checks = checks + 1
    assert(v, msg or "assertion failed")
end

local SM = AuctionatorRemastered.Models.SearchModifiers

-- =========================================================================
-- Test 1: Money Parser
-- =========================================================================
local function TestMoneyParser()
    check(SM.ParseMoney("50g") == 500000, "50g should be 500,000 copper")
    check(SM.ParseMoney("10g50s") == 105000, "10g50s should be 105,000 copper")
    check(SM.ParseMoney("50s") == 5000, "50s should be 5,000 copper")
    check(SM.ParseMoney("25c") == 25, "25c should be 25 copper")
    check(SM.ParseMoney("1g2s3c") == 10203, "1g2s3c should be 10,203 copper")
    check(SM.ParseMoney("100000") == 100000, "Pure number 100000 should be 100,000 copper")
    check(SM.ParseMoney("0g") == 0, "0g should be 0 copper")
    check(SM.ParseMoney("  50g  ") == 500000, "Whitespace should be trimmed")
    check(SM.ParseMoney("") == nil, "Empty string should return nil")
    check(SM.ParseMoney("invalid") == nil, "Invalid text should return nil")
    check(SM.ParseMoney(nil) == nil, "Nil should return nil")
end
TestMoneyParser()

-- =========================================================================
-- Test 2: Quality Parser
-- =========================================================================
local function TestQualityParser()
    check(SM.ParseQuality("poor") == 0, "poor should be 0")
    check(SM.ParseQuality("grey") == 0, "grey should be 0")
    check(SM.ParseQuality("common") == 1, "common should be 1")
    check(SM.ParseQuality("white") == 1, "white should be 1")
    check(SM.ParseQuality("uncommon") == 2, "uncommon should be 2")
    check(SM.ParseQuality("green") == 2, "green should be 2")
    check(SM.ParseQuality("rare") == 3, "rare should be 3")
    check(SM.ParseQuality("blue") == 3, "blue should be 3")
    check(SM.ParseQuality("epic") == 4, "epic should be 4")
    check(SM.ParseQuality("purple") == 4, "purple should be 4")
    check(SM.ParseQuality("q=3") == 3, "q=3 should be 3")
    check(SM.ParseQuality("q=rare") == 3, "q=rare should be 3")
    check(SM.ParseQuality("quality=epic") == 4, "quality=epic should be 4")
    check(SM.ParseQuality("invalid") == nil, "Invalid quality should return nil")
end
TestQualityParser()

-- =========================================================================
-- Test 3: Item Level Parser
-- =========================================================================
local function TestItemLevelParser()
    local minIL, maxIL = SM.ParseItemLevel("ilvl=200-245")
    check(minIL == 200 and maxIL == 245, "ilvl=200-245 should return 200, 245")

    minIL, maxIL = SM.ParseItemLevel("i200-245")
    check(minIL == 200 and maxIL == 245, "i200-245 should return 200, 245")

    minIL, maxIL = SM.ParseItemLevel("ilvl=200+")
    check(minIL == 200 and maxIL == nil, "ilvl=200+ should return 200, nil")

    minIL, maxIL = SM.ParseItemLevel("ilvl=200")
    check(minIL == 200 and maxIL == nil, "ilvl=200 should return 200, nil")

    minIL, maxIL = SM.ParseItemLevel("i200")
    check(minIL == 200 and maxIL == nil, "i200 should return 200, nil")

    minIL, maxIL = SM.ParseItemLevel("not_an_ilvl")
    check(minIL == nil and maxIL == nil, "invalid should return nil, nil")
end
TestItemLevelParser()

-- =========================================================================
-- Test 4: Requirement Level Parser
-- =========================================================================
local function TestReqLevelParser()
    local minL, maxL = SM.ParseLevel("lvl=70-80")
    check(minL == 70 and maxL == 80, "lvl=70-80 should return 70, 80")

    minL, maxL = SM.ParseLevel("req=70-80")
    check(minL == 70 and maxL == 80, "req=70-80 should return 70, 80")

    minL, maxL = SM.ParseLevel("lvl=80")
    check(minL == 80 and maxL == nil, "lvl=80 should return 80, nil")

    minL, maxL = SM.ParseLevel("req=80")
    check(minL == 80 and maxL == nil, "req=80 should return 80, nil")

    minL, maxL = SM.ParseLevel("lvl=70+")
    check(minL == 70 and maxL == nil, "lvl=70+ should return 70, nil")
end
TestReqLevelParser()

-- =========================================================================
-- Test 5: Main Query Parser
-- =========================================================================
local function TestQueryParser()
    -- Clean string without modifiers
    local r1 = SM.Parse("Frostweave Cloth")
    check(r1.cleanSearchText == "Frostweave Cloth", "Clean search text should match")
    check(r1.exact == false, "Exact should be false")
    check(r1.hasModifiers == false, "hasModifiers should be false")

    -- Quotes -> exact match
    local r2 = SM.Parse('"Frostweave Cloth"')
    check(r2.cleanSearchText == "Frostweave Cloth", "Clean search text in quotes")
    check(r2.exact == true, "Quotes should set exact to true")
    check(r2.hasModifiers == true, "hasModifiers should be true")

    -- Slash exact: /exact
    local r3 = SM.Parse("Frostweave Cloth /exact")
    check(r3.cleanSearchText == "Frostweave Cloth", "Clean search text with /exact")
    check(r3.exact == true, "Exact should be true")
    check(r3.hasModifiers == true, "hasModifiers should be true")

    -- Slash without space: Frostweave Cloth/exact
    local r4 = SM.Parse("Frostweave Cloth/exact")
    check(r4.cleanSearchText == "Frostweave Cloth", "Clean search text with /exact (no space)")
    check(r4.exact == true, "Exact should be true (no space)")

    -- Combined modifiers: /rare /max=50g /exact
    local r5 = SM.Parse("Frostweave Cloth /exact /rare /max=50g")
    check(r5.cleanSearchText == "Frostweave Cloth", "Clean search text with multiple modifiers")
    check(r5.exact == true, "Exact should be true")
    check(r5.quality == 3, "Quality should be 3 (rare)")
    check(r5.maxPrice == 500000, "Max price should be 500,000c")
    check(r5.hasModifiers == true, "hasModifiers should be true")

    -- Item level and req level: /ilvl=200-245 /lvl=80
    local r6 = SM.Parse("Greatsword /ilvl=200-245 /lvl=80")
    check(r6.cleanSearchText == "Greatsword", "Clean search text Greatsword")
    check(r6.minItemLevel == 200 and r6.maxItemLevel == 245, "ilvl 200-245")
    check(r6.minLevel == 80, "lvl 80")
end
TestQueryParser()

-- =========================================================================
-- Test 6: Listing Filter Logic
-- =========================================================================
local function TestListingFilter()
    local filter = SM.Parse("Sword /rare /max=50g /ilvl=200-245 /lvl=80")

    local itemPass = {
        name = "Sword of Might",
        quality = 3, -- Rare
        buyoutPrice = 400000, -- 40g (<= 50g)
        stackSize = 1,
        ilvl = 232, -- in [200, 245]
        reqLevel = 80, -- >= 80
    }
    check(SM.FilterListing(itemPass, filter) == true, "Item matching all criteria must pass")

    -- Fail max price
    local itemExpensive = {
        name = "Sword of Greed",
        quality = 3,
        buyoutPrice = 600000, -- 60g (> 50g)
        stackSize = 1,
        ilvl = 232,
        reqLevel = 80,
    }
    check(SM.FilterListing(itemExpensive, filter) == false, "Item over maxPrice must be rejected")

    -- Fail quality
    local itemUncommon = {
        name = "Sword of Green",
        quality = 2, -- Uncommon
        buyoutPrice = 300000,
        stackSize = 1,
        ilvl = 232,
        reqLevel = 80,
    }
    check(SM.FilterListing(itemUncommon, filter) == false, "Item of wrong quality must be rejected")

    -- Fail ilvl
    local itemLowIlvl = {
        name = "Sword of Low",
        quality = 3,
        buyoutPrice = 300000,
        stackSize = 1,
        ilvl = 187, -- < 200
        reqLevel = 80,
    }
    check(SM.FilterListing(itemLowIlvl, filter) == false, "Item below minItemLevel must be rejected")

    -- Test FilterSortedData
    local all = { itemPass, itemExpensive, itemUncommon, itemLowIlvl }
    local filtered = SM.FilterSortedData(all, filter)
    check(#filtered == 1 and filtered[1] == itemPass, "FilterSortedData should retain only matching item")
end
TestListingFilter()

print(string.format("PASS: %d search modifier unit tests passed successfully", checks))
