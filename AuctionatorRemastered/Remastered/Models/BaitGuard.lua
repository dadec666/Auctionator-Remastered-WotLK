-- ============================================================================
-- Auctionator Remastered - Bait / Sniper Trap Guard
-- Protects players from undercutting abnormal dump / bait auctions
-- Adapted for WoW 3.3.5a (WotLK build 12340)
-- ============================================================================

local R = AuctionatorRemastered or {}
AuctionatorRemastered = R

R.Models = R.Models or {}
R.Models.BaitGuard = {}
local BG = R.Models.BaitGuard

-- Default bait detection threshold: 40% discount below market reference
BG.DEFAULT_THRESHOLD_PCT = 40

--- Checks if Bait Guard is enabled in SavedVariables
--- @return boolean
function BG.IsEnabled()
	if AUCTIONATOR_SAVEDVARS and AUCTIONATOR_SAVEDVARS.baitProtection == false then
		return false
	end
	return true
end

--- Retrieves the configured bait threshold percentage
--- @return number
function BG.GetThreshold()
	if AUCTIONATOR_SAVEDVARS and tonumber(AUCTIONATOR_SAVEDVARS.baitThreshold) then
		local t = tonumber(AUCTIONATOR_SAVEDVARS.baitThreshold)
		if t and t > 0 and t < 100 then
			return t
		end
	end
	return BG.DEFAULT_THRESHOLD_PCT
end

--- Checks if a given unit price is considered an abnormal bait / dump price
--- @param unitPrice number The unit buyout price to evaluate
--- @param marketPrice number The historical / reference market price
--- @param thresholdPct number Optional threshold percentage (defaults to configured or 40)
--- @return boolean isBait
--- @return number diffPct Percentage difference (e.g. -60 for 60% below market)
--- @return string|nil reason Reason string if bait
function BG.IsBaitPrice(unitPrice, marketPrice, thresholdPct)
	if not unitPrice or not marketPrice then
		return false, 0, nil
	end
	unitPrice = tonumber(unitPrice)
	marketPrice = tonumber(marketPrice)

	if not unitPrice or not marketPrice or unitPrice <= 0 or marketPrice <= 0 then
		return false, 0, nil
	end

	local threshold = thresholdPct or BG.GetThreshold()
	local diffPct = ((unitPrice - marketPrice) / marketPrice) * 100

	if diffPct <= -threshold then
		return true, diffPct, "underpriced"
	end

	return false, diffPct, nil
end

--- Finds the lowest non-bait competitor from an array of scan entries
--- @param competitorList table Array of scan entries with buyoutPrice and stackSize
--- @param marketPrice number The market reference price
--- @param thresholdPct number Optional threshold percentage
--- @return number|nil lowestNonBaitPrice Unit buyout of lowest legitimate competitor
--- @return table|nil lowestNonBaitEntry The competitor entry table
--- @return number|nil lowestNonBaitIndex The index in the list
function BG.FindLowestNonBaitPrice(competitorList, marketPrice, thresholdPct)
	if not competitorList or #competitorList == 0 then
		return nil, nil, nil
	end

	local threshold = thresholdPct or BG.GetThreshold()

	for i, entry in ipairs(competitorList) do
		local buyout = tonumber(entry.buyoutPrice) or 0
		local stack = math.max(1, tonumber(entry.stackSize) or 1)
		if buyout > 0 then
			local unitBuyout = buyout / stack
			local isBait = false
			if marketPrice and marketPrice > 0 then
				isBait = BG.IsBaitPrice(unitBuyout, marketPrice, threshold)
			end

			if not isBait then
				return unitBuyout, entry, i
			end
		end
	end

	return nil, nil, nil
end

--- Calculates the smart undercut price, avoiding bait traps
--- @param competitorList table Array of competitor scan entries
--- @param marketPrice number Market reference price
--- @param vendorPrice number Vendor floor price
--- @param thresholdPct number Optional threshold percentage
--- @return number targetPrice Calculated target price in copper
--- @return boolean isBaitAvoided True if a lower bait price was ignored
--- @return number referencePrice The price that was undercut or matched
function BG.GetSmartUndercutPrice(competitorList, marketPrice, vendorPrice, thresholdPct)
	vendorPrice = math.max(1, tonumber(vendorPrice) or 1)
	marketPrice = tonumber(marketPrice) or 0
	local threshold = thresholdPct or BG.GetThreshold()

	-- Check if first competitor is bait
	local lowestUnit = nil
	if competitorList and competitorList[1] then
		local b = tonumber(competitorList[1].buyoutPrice) or 0
		local s = math.max(1, tonumber(competitorList[1].stackSize) or 1)
		if b > 0 then
			lowestUnit = b / s
		end
	end

	local firstIsBait = false
	if lowestUnit and marketPrice > 0 then
		firstIsBait = BG.IsBaitPrice(lowestUnit, marketPrice, threshold)
	end

	local lowestNonBait, _ = BG.FindLowestNonBaitPrice(competitorList, marketPrice, threshold)

	if lowestNonBait and lowestNonBait > 1 then
		local target = lowestNonBait - 1
		local avoided = firstIsBait and (lowestUnit < lowestNonBait)
		return target, avoided, lowestNonBait
	end

	-- If all competitors are bait, or no legitimate competitor found
	if marketPrice > 1 then
		local avoided = (lowestUnit ~= nil) and firstIsBait
		return marketPrice - 1, avoided, marketPrice
	end

	-- Fallback to vendor floor
	return vendorPrice, false, vendorPrice
end

--- Scans competitor entries and returns a summary of bait anomalies
--- @param competitorList table Array of scan entries
--- @param marketPrice number Market reference price
--- @param thresholdPct number Optional threshold percentage
--- @return table summary { hasBait, baitCount, lowestBait, lowestNormal, maxDiscountPct }
function BG.AnalyzeCompetitors(competitorList, marketPrice, thresholdPct)
	local summary = {
		hasBait = false,
		baitCount = 0,
		lowestBait = nil,
		lowestNormal = nil,
		maxDiscountPct = 0,
	}

	if not competitorList or #competitorList == 0 or not marketPrice or marketPrice <= 0 then
		return summary
	end

	local threshold = thresholdPct or BG.GetThreshold()

	for _, entry in ipairs(competitorList) do
		local buyout = tonumber(entry.buyoutPrice) or 0
		local stack = math.max(1, tonumber(entry.stackSize) or 1)
		if buyout > 0 then
			local unitBuyout = buyout / stack
			local isBait, diffPct = BG.IsBaitPrice(unitBuyout, marketPrice, threshold)
			if isBait then
				summary.hasBait = true
				summary.baitCount = summary.baitCount + 1
				if not summary.lowestBait or unitBuyout < summary.lowestBait then
					summary.lowestBait = unitBuyout
				end
				local absDiff = math.abs(diffPct)
				if absDiff > summary.maxDiscountPct then
					summary.maxDiscountPct = absDiff
				end
			else
				if not summary.lowestNormal or unitBuyout < summary.lowestNormal then
					summary.lowestNormal = unitBuyout
				end
			end
		end
	end

	return summary
end

-- Global Exports for backward compatibility
_G.Atr_CheckBaitPrice = BG.IsBaitPrice
_G.Atr_GetSmartUndercutPrice = BG.GetSmartUndercutPrice
_G.Atr_FindLowestNonBaitPrice = BG.FindLowestNonBaitPrice
