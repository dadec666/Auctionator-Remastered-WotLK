-- ============================================================================
-- Auctionator Remastered - Price Deviation & Surge Guard
-- Protects players from accidental mispricing:
-- 1) Pricing below vendor sell price (loss compared to vendor)
-- 2) Extreme dump / underpricing (>80% below market reference)
-- 3) Extreme surge / accidental overpricing (>300% above market reference)
-- Adapted for WoW 3.3.5a (WotLK build 12340)
-- ============================================================================

local R = AuctionatorRemastered or {}
AuctionatorRemastered = R

R.Models = R.Models or {}
R.Models.PriceGuard = {}
local PG = R.Models.PriceGuard

-- Default configuration constants
PG.DEFAULT_SURGE_THRESHOLD_PCT = 300 -- >300% above market (4x market price)
PG.DEFAULT_DUMP_THRESHOLD_PCT = 80 -- >80% below market (<20% of market price)
PG.MIN_MARKET_REF_FOR_WARNING = 10000 -- minimum 1 gold market reference to trigger deviation check

--- Checks if Price Deviation Protection is enabled in SavedVariables
--- @return boolean
function PG.IsEnabled()
	if AUCTIONATOR_SAVEDVARS and AUCTIONATOR_SAVEDVARS.priceDeviationProtection == false then
		return false
	end
	return true
end

--- Retrieves the configured surge threshold percentage
--- @return number
function PG.GetSurgeThreshold()
	if AUCTIONATOR_SAVEDVARS and tonumber(AUCTIONATOR_SAVEDVARS.priceSurgeThreshold) then
		local t = tonumber(AUCTIONATOR_SAVEDVARS.priceSurgeThreshold)
		if t and t > 0 then
			return t
		end
	end
	return PG.DEFAULT_SURGE_THRESHOLD_PCT
end

--- Retrieves the configured dump threshold percentage
--- @return number
function PG.GetDumpThreshold()
	if AUCTIONATOR_SAVEDVARS and tonumber(AUCTIONATOR_SAVEDVARS.priceDumpThreshold) then
		local t = tonumber(AUCTIONATOR_SAVEDVARS.priceDumpThreshold)
		if t and t > 0 and t < 100 then
			return t
		end
	end
	return PG.DEFAULT_DUMP_THRESHOLD_PCT
end

--- Evaluates whether a proposed unit price deviates abnormally from reference prices
--- @param unitPrice number The unit price to evaluate (in copper)
--- @param marketRef number The market reference / historical median price (in copper)
--- @param vendorPrice number The item's vendor sell floor (in copper)
--- @param customSurgePct number Optional custom surge threshold
--- @param customDumpPct number Optional custom dump threshold
--- @return table evaluation Result table with isAnomaly, anomalyType, diffPct, etc.
function PG.EvaluatePrice(unitPrice, marketRef, vendorPrice, customSurgePct, customDumpPct)
	unitPrice = tonumber(unitPrice) or 0
	marketRef = tonumber(marketRef) or 0
	vendorPrice = tonumber(vendorPrice) or 0

	local result = {
		isAnomaly = false,
		anomalyType = nil,
		diffPct = 0,
		unitPrice = unitPrice,
		marketRef = marketRef,
		vendorPrice = vendorPrice,
	}

	if unitPrice <= 0 then
		return result
	end

	-- 1. Check Vendor Floor: Selling on AH below vendor price causes a net loss!
	if vendorPrice > 0 and unitPrice < vendorPrice then
		result.isAnomaly = true
		result.anomalyType = "BELOW_VENDOR"
		result.diffPct = ((unitPrice - vendorPrice) / vendorPrice) * 100
		return result
	end

	-- Deviation checks require a meaningful market reference (>= 1 gold)
	if marketRef < PG.MIN_MARKET_REF_FOR_WARNING then
		return result
	end

	local surgeThreshold = customSurgePct or PG.GetSurgeThreshold()
	local dumpThreshold = customDumpPct or PG.GetDumpThreshold()
	local diffPct = ((unitPrice - marketRef) / marketRef) * 100
	result.diffPct = diffPct

	-- 2. Check Extreme Dump: Unit price is significantly below market (e.g. missed a zero)
	if diffPct <= -dumpThreshold then
		result.isAnomaly = true
		result.anomalyType = "EXTREME_LOW"
		return result
	end

	-- 3. Check Price Surge: Unit price is abnormally higher than market (e.g. extra zeros or typo)
	if diffPct >= surgeThreshold then
		result.isAnomaly = true
		result.anomalyType = "EXTREME_HIGH"
		return result
	end

	return result
end

--- Formats a short inline badge warning for the Sell Terminal
--- @param eval table The evaluation table from EvaluatePrice
--- @return string badgeText, string hexColor
function PG.GetBadgeText(eval)
	if not eval or not eval.isAnomaly then
		return "", "ffffff"
	end

	local Z = _G.ZT or function(s)
		return s
	end
	if eval.anomalyType == "BELOW_VENDOR" then
		return "⚠️ " .. Z("Below Vendor Floor"), "ff4444"
	elseif eval.anomalyType == "EXTREME_LOW" then
		return string.format("⚠️ " .. Z("Extreme Low Price (-%d%%)"), math.abs(math.floor(eval.diffPct))), "ff9900"
	elseif eval.anomalyType == "EXTREME_HIGH" then
		return string.format("⚠️ " .. Z("Price Surge (+%d%%)"), math.floor(eval.diffPct)), "ff9900"
	end

	return "", "ffffff"
end

--- Formats a detailed confirmation dialog text when attempting to post an anomalous price
--- @param eval table The evaluation table from EvaluatePrice
--- @param moneyFunc function Price formatting function (e.g. gAtrZC.priceToMoneyString)
--- @return string dialogText
function PG.GetConfirmationText(eval, moneyFunc)
	local money = moneyFunc or function(c)
		return tostring(c) .. "c"
	end
	local Z = _G.ZT or function(s)
		return s
	end

	if not eval or not eval.isAnomaly then
		return ""
	end

	if eval.anomalyType == "BELOW_VENDOR" then
		return string.format(
			Z(
				"Warning: Buyout (%s) is lower than the vendor sell price (%s)!\n\nSelling to a vendor gives more money without AH deposit or cut.\n\nAre you sure you want to post?"
			),
			money(eval.unitPrice),
			money(eval.vendorPrice)
		)
	elseif eval.anomalyType == "EXTREME_LOW" then
		return string.format(
			Z(
				"Warning: Buyout (%s) is %d%% below the market reference (%s)!\n\nDid you forget a zero?\n\nAre you sure you want to post at this price?"
			),
			money(eval.unitPrice),
			math.abs(math.floor(eval.diffPct)),
			money(eval.marketRef)
		)
	elseif eval.anomalyType == "EXTREME_HIGH" then
		return string.format(
			Z(
				"Warning: Buyout (%s) is %d%% above the market reference (%s)!\n\nThis is an extreme price surge. The auction deposit may be lost if it does not sell.\n\nAre you sure you want to post at this price?"
			),
			money(eval.unitPrice),
			math.floor(eval.diffPct),
			money(eval.marketRef)
		)
	end

	return Z("Are you sure you want to post at this price?")
end

-- Global exports for legacy interoperability
_G.Atr_CheckPriceDeviation = PG.EvaluatePrice
_G.Atr_GetPriceDeviationBadge = PG.GetBadgeText
_G.Atr_GetPriceDeviationConfirmation = PG.GetConfirmationText
