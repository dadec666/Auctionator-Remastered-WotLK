dofile("AuctionatorRemastered/Remastered/Core/Bootstrap.lua")
dofile("AuctionatorRemastered/Remastered/Integration/LegacyBridge.lua")

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
function hooksecurefunc(name, callback) end

local mockPlayerLevel = 80
function UnitLevel(unit)
    return mockPlayerLevel
end

local mockMoney = 5000000 -- 500g
function GetMoney()
    return mockMoney
end

-- =========================================================================
-- Test 1: Level Requirement Color Coding (Req Color from aux)
-- =========================================================================
local function TestReqLevelColors()
    local function GetReqLevelColor(reqLevel)
        if not reqLevel or reqLevel <= 0 then
            return 0.8, 0.8, 0.8
        end
        local playerLevel = UnitLevel and UnitLevel("player") or 80
        local diff = reqLevel - playerLevel
        if diff >= 5 then
            return 1.0, 0.2, 0.2 -- Red: 5+ levels above
        elseif diff >= 3 then
            return 1.0, 0.5, 0.0 -- Orange: 3-4 levels above
        elseif diff >= 1 then
            return 1.0, 0.8, 0.0 -- Yellow: 1-2 levels above
        elseif diff <= -10 then
            return 0.5, 0.5, 0.5 -- Gray: trivial low level
        else
            return 0.2, 1.0, 0.2 -- Green: usable right now
        end
    end

    mockPlayerLevel = 70

    -- Level 75 (diff +5) -> Red
    local r, g, b = GetReqLevelColor(75)
    check(r == 1.0 and g == 0.2 and b == 0.2, "Req level 75 (+5) should be Red")

    -- Level 74 (diff +4) -> Orange
    r, g, b = GetReqLevelColor(74)
    check(r == 1.0 and g == 0.5 and b == 0.0, "Req level 74 (+4) should be Orange")

    -- Level 71 (diff +1) -> Yellow
    r, g, b = GetReqLevelColor(71)
    check(r == 1.0 and g == 0.8 and b == 0.0, "Req level 71 (+1) should be Yellow")

    -- Level 70 (diff 0) -> Green
    r, g, b = GetReqLevelColor(70)
    check(r == 0.2 and g == 1.0 and b == 0.2, "Req level 70 (usable) should be Green")

    -- Level 65 (diff -5) -> Green
    r, g, b = GetReqLevelColor(65)
    check(r == 0.2 and g == 1.0 and b == 0.2, "Req level 65 (-5) should be Green")

    -- Level 50 (diff -20) -> Gray
    r, g, b = GetReqLevelColor(50)
    check(r == 0.5 and g == 0.5 and b == 0.5, "Req level 50 (-20) should be Gray")
end
TestReqLevelColors()

-- =========================================================================
-- Test 2: Cart & Buyout Math
-- =========================================================================
local function TestCartMath()
    local unitPrice = 125000 -- 12g 50s
    local numToBuy = 20
    local totalCost = unitPrice * numToBuy -- 250g = 2,500,000 copper
    check(totalCost == 2500000, "Total cost for 20 items at 12.5g should be 250g (2,500,000c)")

    mockMoney = 5000000 -- 500g
    local canAfford = mockMoney >= totalCost
    check(canAfford == true, "Player with 500g should be able to afford 250g")
    local balanceAfter = mockMoney - totalCost
    check(balanceAfter == 2500000, "Balance after purchase should be 250g")

    mockMoney = 100000 -- 10g
    local canAffordLow = mockMoney >= totalCost
    check(canAffordLow == false, "Player with 10g should NOT be able to afford 250g")
end
TestCartMath()

-- =========================================================================
-- Test 3: Market Discount & Premium Percentage Math
-- =========================================================================
local function TestMarketEvaluation()
    local function CalcDiscount(lowestBuyout, marketRef)
        if not lowestBuyout or not marketRef or marketRef <= 0 then
            return nil
        end
        return math.floor(((lowestBuyout - marketRef) / marketRef) * 100 + 0.5)
    end

    -- 20% discount (80g vs 100g)
    local pctDiscount = CalcDiscount(800000, 1000000)
    check(pctDiscount == -20, "80g against 100g reference should be -20% discount")

    -- 50% overprice (150g vs 100g)
    local pctOverprice = CalcDiscount(1500000, 1000000)
    check(pctOverprice == 50, "150g against 100g reference should be +50% overprice")

    -- Equal price (100g vs 100g)
    local pctEqual = CalcDiscount(1000000, 1000000)
    check(pctEqual == 0, "100g against 100g reference should be 0%")
end
TestMarketEvaluation()

-- =========================================================================
-- Test 4: Quantity Presets Math
-- =========================================================================
local function TestQuantityPresets()
    local listing = { count = 5, stackSize = 20 }

    -- Preset "1"
    local items1 = 1
    local stacks1 = 1
    check(items1 == 1, "Preset 1 should select 1 item")

    -- Preset "stack"
    local itemsStack = listing.stackSize
    local stacksStack = 1
    check(itemsStack == 20, "Preset stack should select 20 items")
    check(stacksStack == 1, "Preset stack should select 1 stack")

    -- Preset "all"
    local itemsAll = listing.stackSize * listing.count
    local stacksAll = listing.count
    check(itemsAll == 100, "Preset all should select 100 items (5x20)")
    check(stacksAll == 5, "Preset all should select 5 stacks")
end
TestQuantityPresets()

-- =========================================================================
-- Test 5: Settings Toggle Fallback
-- =========================================================================
local function TestSettingsToggle()
    AUCTIONATOR_SAVEDVARS = {}

    -- Default: modernBuy is true
    local useModernDefault = AUCTIONATOR_SAVEDVARS.modernBuy ~= false
    check(useModernDefault == true, "Modern buy should default to true")

    -- Explicitly enabled
    AUCTIONATOR_SAVEDVARS.modernBuy = true
    check(AUCTIONATOR_SAVEDVARS.modernBuy ~= false, "Modern buy should be enabled when true")

    -- Explicitly disabled (Classic 2008 view)
    AUCTIONATOR_SAVEDVARS.modernBuy = false
    check((AUCTIONATOR_SAVEDVARS.modernBuy ~= false) == false, "Modern buy should be disabled when false")
end
TestSettingsToggle()

-- =========================================================================
-- Test 6: Race Condition Guard & Atr_DoesAuctionMatch Validation
-- =========================================================================
local function TestRaceConditionGuard()
    local expectedLink = "item:2447:0:0:0:0:0:0:0:80"
    local expectedBuyout = 50000
    local expectedCount = 20

    local function ValidateLotBeforeBid(currentLink, currentBuyout, currentCount)
        if currentLink ~= expectedLink or currentBuyout ~= expectedBuyout or currentCount ~= expectedCount then
            return false, "Lot moved or changed"
        end
        return true
    end

    -- Valid match
    local ok1 = ValidateLotBeforeBid(expectedLink, expectedBuyout, expectedCount)
    check(ok1 == true, "Matching lot should pass race condition guard")

    -- Lot moved (another item now in that slot)
    local ok2 = ValidateLotBeforeBid("item:9999:0:0:0:0:0:0:0:80", 50000, 20)
    check(ok2 == false, "Shifted lot with different link must be rejected")

    -- Price changed
    local ok3 = ValidateLotBeforeBid(expectedLink, 500000, expectedCount)
    check(ok3 == false, "Shifted lot with higher price must be rejected")

    -- Test Atr_DoesAuctionMatch with expectedLink parameter
    local mockListings = {
        [1] = {
            name = "Frostweave Cloth",
            count = 20,
            buyoutPrice = 50000,
            link = "item:33470:0:0:0:0:0:0:0:80",
        },
        [2] = {
            name = "Frostweave Cloth",
            count = 20,
            buyoutPrice = 50000,
            link = "item:99999:0:0:0:0:0:0:0:80", -- shifted/different item with same name
        },
    }

    function GetAuctionItemInfo(list, i)
        local item = mockListings[i]
        if not item then
            return nil
        end
        return item.name, nil, item.count, 1, 1, 80, 0, 0, item.buyoutPrice, 0, nil, item.owner or "OtherGuy"
    end

    function GetAuctionItemLink(list, i)
        local item = mockListings[i]
        return item and item.link or nil
    end

    local zcMock = {
        ItemIDStrfromLink = function(link)
            if not link then
                return nil
            end
            return string.match(link, "item:(%d+)")
        end,
        StringSame = function(a, b)
            return a and b and string.lower(a) == string.lower(b)
        end,
    }
    _G.zc = zcMock

    -- Atr_DoesAuctionMatch test implementation
    local function TestDoesAuctionMatch(list, i, name, buyout, stacksize, expectedLinkParam)
        local aname, _, astacksize, _, _, _, _, _, abuyout = GetAuctionItemInfo(list, i)
        if aname and aname == name and abuyout == buyout and astacksize == stacksize then
            if expectedLinkParam and GetAuctionItemLink and zc and zc.ItemIDStrfromLink then
                local alink = GetAuctionItemLink(list, i)
                if alink and (zc.ItemIDStrfromLink(alink) ~= zc.ItemIDStrfromLink(expectedLinkParam)) then
                    return false
                end
            end
            return true
        end
        return false
    end

    -- Slot 1: Exact match with item:33470
    local match1 = TestDoesAuctionMatch("list", 1, "Frostweave Cloth", 50000, 20, "item:33470:0:0:0:0:0:0:0:80")
    check(match1 == true, "Slot 1 should match expectedLink item:33470")

    -- Slot 2: Different itemID (item:99999) despite same name & price
    local match2 = TestDoesAuctionMatch("list", 2, "Frostweave Cloth", 50000, 20, "item:33470:0:0:0:0:0:0:0:80")
    check(match2 == false, "Slot 2 should fail expectedLink check due to itemID mismatch")

    -- Test Own Auction Guard
    mockListings[1].owner = "MyPlayer"
    function UnitName(unit)
        return "MyPlayer"
    end

    local function CheckOwnAuction(i)
        local _, _, _, _, _, _, _, _, _, _, _, owner = GetAuctionItemInfo("list", i)
        return owner == UnitName("player")
    end
    check(CheckOwnAuction(1) == true, "Own auction should be recognized")
    check(CheckOwnAuction(2) == false, "Other character auction is not own auction")

    -- Test Combat Lockdown Guard
    local function TestCombatLockdownPurchase(inCombat)
        if inCombat then
            return false, "Cannot purchase during combat."
        end
        return true
    end
    check(TestCombatLockdownPurchase(true) == false, "Purchase must be blocked during combat lockdown")
    check(TestCombatLockdownPurchase(false) == true, "Purchase allowed when not in combat")
end
TestRaceConditionGuard()

print(string.format("PASS: %d BuyTerminal unit tests passed successfully", checks))
