-- tools/tests/test_price_deviation_guard.lua
-- Unit test suite for Price Deviation & Surge Guard (AuctionatorRemastered.Models.PriceGuard)

local checks = 0
local function check(ok, msg)
	checks = checks + 1
	if not ok then
		error("CHECK FAILED: " .. tostring(msg), 2)
	end
end

-- Mock WoW environment
function ZT(s)
	return s
end

-- Load Bootstrap and Model
dofile("AuctionatorRemastered/Remastered/Core/Bootstrap.lua")
dofile("AuctionatorRemastered/Remastered/Models/PriceGuard.lua")

local PG = AuctionatorRemastered.Models.PriceGuard
check(type(PG) == "table", "PriceGuard model loaded successfully")

-- Test 1: Default configuration & toggles
check(PG.IsEnabled() == true, "PriceGuard is enabled by default")
check(PG.GetSurgeThreshold() == 300, "Default surge threshold is 300%")
check(PG.GetDumpThreshold() == 80, "Default dump threshold is 80%")

-- Toggle disable
AUCTIONATOR_SAVEDVARS = { priceDeviationProtection = false }
check(PG.IsEnabled() == false, "PriceGuard honors disabled setting")
AUCTIONATOR_SAVEDVARS.priceDeviationProtection = true
check(PG.IsEnabled() == true, "PriceGuard honors enabled setting")

-- Custom thresholds
AUCTIONATOR_SAVEDVARS.priceSurgeThreshold = 250
AUCTIONATOR_SAVEDVARS.priceDumpThreshold = 70
check(PG.GetSurgeThreshold() == 250, "Custom surge threshold 250%")
check(PG.GetDumpThreshold() == 70, "Custom dump threshold 70%")
AUCTIONATOR_SAVEDVARS = {}

-- Test 2: Vendor floor check
local vendorPrice = 10000 -- 1 gold
local marketRef = 50000 -- 5 gold

-- Buyout below vendor price
local eval = PG.EvaluatePrice(8000, marketRef, vendorPrice)
check(eval.isAnomaly == true, "Buyout below vendor price detected as anomaly")
check(eval.anomalyType == "BELOW_VENDOR", "Anomaly type is BELOW_VENDOR")
check(eval.diffPct < 0, "diffPct is negative vs vendor")
local badgeText, hexColor = PG.GetBadgeText(eval)
check(badgeText:find("Below Vendor Floor", 1, true) ~= nil, "Badge text warns below vendor")
check(hexColor == "ff4444", "Below vendor badge is red")

-- Buyout exactly equal to vendor price with normal market ref
eval = PG.EvaluatePrice(10000, 12000, vendorPrice)
check(eval.isAnomaly == false, "Buyout equal to vendor price with normal market ref is safe")

-- Test 3: Normal pricing within reasonable boundaries
-- 10% below market
eval = PG.EvaluatePrice(45000, marketRef, vendorPrice)
check(eval.isAnomaly == false, "10% below market is normal")

-- 50% above market
eval = PG.EvaluatePrice(75000, marketRef, vendorPrice)
check(eval.isAnomaly == false, "50% above market is normal")

-- 200% above market (not exceeding 300%)
eval = PG.EvaluatePrice(150000, marketRef, vendorPrice)
check(eval.isAnomaly == false, "200% above market is within 300% threshold")

-- Test 4: Extreme Low / Dump Price (e.g. missed a zero)
-- 85% below market (e.g. 7,500c vs 50,000c)
eval = PG.EvaluatePrice(7500, marketRef, 5000)
check(eval.isAnomaly == true, "85% below market detected as anomaly")
check(eval.anomalyType == "EXTREME_LOW", "Anomaly type is EXTREME_LOW")
check(eval.diffPct == -85, "diffPct is -85%")
badgeText, hexColor = PG.GetBadgeText(eval)
check(badgeText:find("Extreme Low Price", 1, true) ~= nil, "Badge warns extreme low price")
check(badgeText:find("-85%", 1, true) ~= nil, "Badge shows -85% discount")
check(hexColor == "ff9900", "Badge color is amber")

local confirmText = PG.GetConfirmationText(eval, function(c)
	return tostring(c)
end)
check(confirmText:find("below the market reference", 1, true) ~= nil, "Confirmation text mentions below market")
check(confirmText:find("Did you forget a zero?", 1, true) ~= nil, "Confirmation warns about missed zero")

-- Test 5: Extreme Surge / Accidental Overpricing (e.g. extra zeros)
-- 400% above market (5x market price, e.g. 250,000c vs 50,000c)
eval = PG.EvaluatePrice(250000, marketRef, vendorPrice)
check(eval.isAnomaly == true, "400% above market detected as price surge")
check(eval.anomalyType == "EXTREME_HIGH", "Anomaly type is EXTREME_HIGH")
check(eval.diffPct == 400, "diffPct is +400%")
badgeText, hexColor = PG.GetBadgeText(eval)
check(badgeText:find("Price Surge", 1, true) ~= nil, "Badge warns price surge")
check(badgeText:find("+400%", 1, true) ~= nil, "Badge shows +400%")
check(hexColor == "ff9900", "Surge badge color is amber")

confirmText = PG.GetConfirmationText(eval, function(c)
	return tostring(c)
end)
check(confirmText:find("above the market reference", 1, true) ~= nil, "Confirmation text mentions above market")
check(confirmText:find("extreme price surge", 1, true) ~= nil, "Confirmation warns about lost deposit")

-- Test 6: Low value items (< 1 gold market reference)
-- Avoid false alarms on cheap grey items with erratic copper market data
eval = PG.EvaluatePrice(500, 100, 50)
check(eval.isAnomaly == false, "Market ref < 1 gold does not trigger deviation check")

-- But below-vendor is ALWAYS triggered even on cheap items
eval = PG.EvaluatePrice(30, 100, 50)
check(eval.isAnomaly == true and eval.anomalyType == "BELOW_VENDOR", "Below vendor check applies to all items")

-- Test 7: Global exports interoperability
check(type(_G.Atr_CheckPriceDeviation) == "function", "Atr_CheckPriceDeviation exported globally")
check(type(_G.Atr_GetPriceDeviationBadge) == "function", "Atr_GetPriceDeviationBadge exported globally")
check(type(_G.Atr_GetPriceDeviationConfirmation) == "function", "Atr_GetPriceDeviationConfirmation exported globally")

local globalEval = Atr_CheckPriceDeviation(300000, 50000, 1000)
check(globalEval.isAnomaly == true and globalEval.anomalyType == "EXTREME_HIGH", "Global export evaluates correctly")

print("PASS: " .. checks .. " checks passed in test_price_deviation_guard.lua")
