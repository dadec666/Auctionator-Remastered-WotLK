-- ============================================================================
-- Auctionator Remastered - Smart Bag Splitter & Auto-fill
-- Calculates smart stack distributions, handles inventory remainders,
-- and validates bag capacity for auction batching.
-- Adapted for WoW 3.3.5a (WotLK build 12340)
-- ============================================================================

local R = AuctionatorRemastered or {}
AuctionatorRemastered = R

R.Models = R.Models or {}
R.Models.StackSplitter = {}
local SS = R.Models.StackSplitter

--- Calculates smart stack distribution for an item in bags
--- @param totalCount number Total number of items in player's bags
--- @param maxStack number Max stack size for the item
--- @param preferredSize number Optional user-preferred stack size
--- @return table distribution Calculation details {size, count, posted, remainder, isExact, summary}
function SS.CalculateSmartDistribution(totalCount, maxStack, preferredSize)
    totalCount = math.max(0, tonumber(totalCount) or 0)
    maxStack = math.max(1, tonumber(maxStack) or 1)
    preferredSize = tonumber(preferredSize)

    local size = maxStack
    if preferredSize and preferredSize > 0 and preferredSize <= maxStack then
        size = preferredSize
    end

    -- Size cannot exceed available items
    if size > totalCount and totalCount > 0 then
        size = totalCount
    end

    local count = 0
    if size > 0 then
        count = math.floor(totalCount / size)
    end
    if count <= 0 and totalCount > 0 then
        count = 1
        size = totalCount
    end

    local posted = size * count
    local remainder = math.max(0, totalCount - posted)
    local isExact = (remainder == 0)

    local Z = _G.ZT or function(s)
        return s
    end
    local summary
    if totalCount == 0 then
        summary = Z("No items in bags")
    elseif isExact then
        if count == 1 and size == 1 then
            summary = Z("Posting 1 item")
        elseif count == 1 then
            summary = string.format(Z("Posting 1 stack of %d"), size)
        else
            summary = string.format(Z("Posting all %d items (%d × %d)"), totalCount, count, size)
        end
    else
        summary = string.format(Z("Posting %d of %d items (%d left in bags)"), posted, totalCount, remainder)
    end

    return {
        size = size,
        count = count,
        posted = posted,
        remainder = remainder,
        isExact = isExact,
        summary = summary,
    }
end

--- Returns the stack parameters for posting the remaining leftovers
--- @param totalCount number Total number of items in player's bags
--- @param currentSize number Current stack size
--- @param currentCount number Current number of stacks
--- @return number remainderSize, number remainderCount
function SS.GetRemainderPreset(totalCount, currentSize, currentCount)
    totalCount = math.max(0, tonumber(totalCount) or 0)
    currentSize = math.max(1, tonumber(currentSize) or 1)
    currentCount = math.max(0, tonumber(currentCount) or 0)

    local posted = currentSize * currentCount
    local remainder = math.max(0, totalCount - posted)

    if remainder > 0 then
        return remainder, 1
    end
    return 0, 0
end

--- Validates whether the requested stack size and count can be fulfilled from bags
--- @param totalCount number Total number of items in player's bags
--- @param stackSize number Requested stack size
--- @param numStacks number Requested number of stacks
--- @param maxStack number Max allowable stack size for the item
--- @return boolean isValid
--- @return string status Status code: "OK", "OVERFLOW", "ZERO_SIZE", "ZERO_COUNT", "MAX_STACK_EXCEEDED"
--- @return string message Localized status description
--- @return number needed Total items needed
function SS.ValidateStacking(totalCount, stackSize, numStacks, maxStack)
    totalCount = math.max(0, tonumber(totalCount) or 0)
    stackSize = tonumber(stackSize) or 0
    numStacks = tonumber(numStacks) or 0
    maxStack = math.max(1, tonumber(maxStack) or 1)

    local Z = _G.ZT or function(s)
        return s
    end

    if stackSize <= 0 then
        return false, "ZERO_SIZE", Z("Stack size must be at least 1"), 0
    end
    if numStacks <= 0 then
        return false, "ZERO_COUNT", Z("Number of stacks must be at least 1"), 0
    end
    if stackSize > maxStack then
        return false,
            "MAX_STACK_EXCEEDED",
            string.format(Z("Stack size cannot exceed max stack (%d)"), maxStack),
            stackSize * numStacks
    end

    local needed = stackSize * numStacks
    if needed > totalCount then
        local missing = needed - totalCount
        return false,
            "OVERFLOW",
            string.format(Z("⚠️ Need %d items, only %d in bags (missing %d)"), needed, totalCount, missing),
            needed
    end

    local remainder = totalCount - needed
    local msg
    if remainder > 0 then
        msg = string.format(Z("Posting %d of %d items (%d left in bags)"), needed, totalCount, remainder)
    else
        msg = string.format(Z("Posting all %d items (%d × %d)"), totalCount, numStacks, stackSize)
    end

    return true, "OK", msg, needed
end

-- Global exports for legacy and external interoperability
_G.Atr_CalculateSmartDistribution = SS.CalculateSmartDistribution
_G.Atr_GetRemainderPreset = SS.GetRemainderPreset
_G.Atr_ValidateStacking = SS.ValidateStacking
