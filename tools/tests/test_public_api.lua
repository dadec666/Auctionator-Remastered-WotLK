dofile("AuctionatorRemastered/Remastered/Core/Bootstrap.lua")
dofile("AuctionatorRemastered/Remastered/Integration/PublicAPI.lua")

local checks = 0
local function check(v, msg)
    checks = checks + 1
    assert(v, msg or "assertion failed")
end

local API = AuctionatorRemasteredAPI
check(API ~= nil, "AuctionatorRemasteredAPI must be exposed globally")
check(API == AuctionatorRemastered.API, "API must match AuctionatorRemastered.API")

-- =========================================================================
-- Test 1: Version & Status
-- =========================================================================
check(API.GetVersion() == "0.9.0-beta.2", "Version should be 0.9.0-beta.2")

AuctionFrame = {
    shown = false,
    IsShown = function(self)
        return self.shown
    end,
}
check(API.IsOpen() == false, "IsOpen should be false when AuctionFrame is hidden")
AuctionFrame.shown = true
check(API.IsOpen() == true, "IsOpen should be true when AuctionFrame is shown")

-- =========================================================================
-- Test 2: Price Lookups
-- =========================================================================
function Atr_GetAuctionPrice(item)
    if item == "Frostweave Cloth" or item == "item:33470" then
        return 15000 -- 1g 50s
    end
    return nil
end

check(API.GetPrice("Frostweave Cloth") == 15000, "GetPrice should return 15,000c")
check(API.GetPrice("item:33470") == 15000, "GetPrice with itemID string")
check(API.GetPrice("Unknown Item") == nil, "GetPrice should return nil for unknown")
check(API.GetPrice(nil) == nil, "GetPrice with nil")

-- =========================================================================
-- Test 3: Market Price & Historical Fallback
-- =========================================================================
function Atr_DatabaseRecord(item)
    if item == "Frostweave Cloth" then
        return { marketPrice = 18000 }
    end
    return nil
end

check(API.GetMarketPrice("Frostweave Cloth") == 18000, "GetMarketPrice should return 18,000c from database record")
-- Fallback when no database record exists
check(API.GetMarketPrice("item:33470") == 15000, "GetMarketPrice should fall back to current price if no DB record")

-- =========================================================================
-- Test 4: Vendor & Disenchant
-- =========================================================================
function Atr_GetSellValue(item)
    if item == "Frostweave Cloth" then
        return 250 -- 2s 50c
    end
    return nil
end

function GetItemInfo(item)
    return "Mock", "item:mock", 1, 80, 1, "Armor", "Cloth", 20, "INV", "icon", 250
end

check(API.GetVendorPrice("Frostweave Cloth") == 250, "GetVendorPrice should return 250c")

function Atr_GetDisenchantValue(item)
    if item == "Magic Wand" then
        return 4500
    end
    return nil
end

check(API.GetDisenchantPrice("Magic Wand") == 4500, "GetDisenchantPrice should return 4500c")
check(API.GetDisenchantPrice("Frostweave Cloth") == nil, "GetDisenchantPrice nil for non-de")

-- =========================================================================
-- Test 5: Consolidated Stats
-- =========================================================================
local stats = API.GetItemStats("Frostweave Cloth")
check(stats.currentPrice == 15000, "Stats currentPrice")
check(stats.marketPrice == 18000, "Stats marketPrice")
check(stats.vendorPrice == 250, "Stats vendorPrice")
check(stats.disenchantPrice == nil, "Stats disenchantPrice")

-- =========================================================================
-- Test 6: Search Trigger
-- =========================================================================
local searchedQuery = nil
function Atr_TriggerBuySearch(query)
    searchedQuery = query
end

AuctionFrame.shown = false
check(API.Search("Frostweave Cloth") == false, "Search should return false if AH is closed")

AuctionFrame.shown = true
check(API.Search("Frostweave Cloth") == true, "Search should return true if AH is open")
check(searchedQuery == "Frostweave Cloth", "Search query forwarded correctly")

check(API.Search("Frostweave Cloth", true) == true, "Exact search should succeed")
check(searchedQuery == '"Frostweave Cloth"', "Exact search should wrap query in quotes")

-- =========================================================================
-- Test 7: Money Formatting
-- =========================================================================
check(API.FormatMoney(500000) == "50g 0s 0c", "500000 copper formatted")
check(API.FormatMoney(105025) == "10g 50s 25c", "105025 copper formatted")
check(API.FormatMoney(0) == "0g 0s 0c", "0 copper formatted")

print(string.format("PASS: %d Public API unit tests passed successfully", checks))
