-- ============================================================================
-- Auctionator Remastered - Linear Search Modifier Parser
-- Adapted from aux-forever concepts for WoW 3.3.5a (WotLK build 12340)
-- Supports inline search modifiers: /exact, /rare, /ilvl=X-Y, /lvl=X, /max=50g
-- ============================================================================

local addonName, addonTable = ...
local R = AuctionatorRemastered or {}
AuctionatorRemastered = R

R.Models = R.Models or {}
R.Models.SearchModifiers = {}
local SM = R.Models.SearchModifiers

-- Helper: Trim whitespace
local function trim(s)
    if not s then
        return ""
    end
    return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

-- ============================================================================
-- Money Parser (e.g. "50g", "10g50s", "50s", "25c", "100000") -> copper
-- ============================================================================
function SM.ParseMoney(str)
    if not str or str == "" then
        return nil
    end
    str = string.lower(trim(str))

    -- Pure integer copper: e.g. "500000"
    if tonumber(str) then
        return tonumber(str)
    end

    local g = tonumber(string.match(str, "(%d+)g")) or 0
    local s = tonumber(string.match(str, "(%d+)s")) or 0
    local c = tonumber(string.match(str, "(%d+)c")) or 0

    local total = g * 10000 + s * 100 + c
    if total > 0 or string.find(str, "0c") or string.find(str, "0s") or string.find(str, "0g") then
        return total
    end

    return nil
end

-- ============================================================================
-- Quality Parser (e.g. "poor", "rare", "q=3", "quality=epic") -> 0..4
-- ============================================================================
function SM.ParseQuality(str)
    if not str or str == "" then
        return nil
    end
    local s = string.lower(trim(str))
    s = string.gsub(s, "^q=", "")
    s = string.gsub(s, "^quality=", "")

    local num = tonumber(s)
    if num and num >= 0 and num <= 4 then
        return num
    end

    local rarityMap = {
        poor = 0,
        grey = 0,
        gray = 0,
        common = 1,
        white = 1,
        uncommon = 2,
        green = 2,
        rare = 3,
        blue = 3,
        epic = 4,
        purple = 4,
    }

    return rarityMap[s]
end

-- ============================================================================
-- Item Level Parser (e.g. "ilvl=200-245", "ilvl=200", "i200", "ilvl=200+")
-- ============================================================================
function SM.ParseItemLevel(str)
    if not str or str == "" then
        return nil, nil
    end
    local s = string.lower(trim(str))
    s = string.gsub(s, "^ilvl=", "")
    s = string.gsub(s, "^i", "")

    -- Range: 200-245
    local minIL, maxIL = string.match(s, "^(%d+)%s*%-%s*(%d+)")
    if minIL and maxIL then
        return tonumber(minIL), tonumber(maxIL)
    end

    -- Min plus: 200+
    local plusIL = string.match(s, "^(%d+)%+")
    if plusIL then
        return tonumber(plusIL), nil
    end

    -- Single: 200
    local singleIL = string.match(s, "^(%d+)$")
    if singleIL then
        return tonumber(singleIL), nil
    end

    return nil, nil
end

-- ============================================================================
-- Character Requirement Level Parser (e.g. "lvl=70-80", "req=80", "lvl=80+")
-- ============================================================================
function SM.ParseLevel(str)
    if not str or str == "" then
        return nil, nil
    end
    local s = string.lower(trim(str))
    s = string.gsub(s, "^lvl=", "")
    s = string.gsub(s, "^req=", "")
    s = string.gsub(s, "^level=", "")

    -- Range: 70-80
    local minL, maxL = string.match(s, "^(%d+)%s*%-%s*(%d+)")
    if minL and maxL then
        return tonumber(minL), tonumber(maxL)
    end

    -- Min plus: 70+
    local plusL = string.match(s, "^(%d+)%+")
    if plusL then
        return tonumber(plusL), nil
    end

    -- Single: 80
    local singleL = string.match(s, "^(%d+)$")
    if singleL then
        return tonumber(singleL), nil
    end

    return nil, nil
end

-- ============================================================================
-- Main Search Query Parser: Extracts modifiers and returns clean search text
-- ============================================================================
function SM.Parse(rawText)
    if not rawText or rawText == "" then
        return {
            rawText = "",
            cleanSearchText = "",
            exact = false,
            quality = nil,
            minLevel = nil,
            maxLevel = nil,
            minItemLevel = nil,
            maxItemLevel = nil,
            maxPrice = nil,
            hasModifiers = false,
        }
    end

    local text = trim(rawText)
    local exact = false
    local quality = nil
    local minLevel, maxLevel = nil, nil
    local minItemLevel, maxItemLevel = nil, nil
    local maxPrice = nil
    local hasModifiers = false

    -- Check outer quotes for exact match: "Frostweave Cloth"
    if string.sub(text, 1, 1) == '"' and string.sub(text, -1) == '"' and string.len(text) > 1 then
        exact = true
        text = string.sub(text, 2, -2)
        hasModifiers = true
    end

    -- Check slash delimiter
    if string.find(text, "/") then
        local parts = {}
        for part in string.gmatch(text, "[^/]+") do
            table.insert(parts, trim(part))
        end

        local cleanParts = {}
        for _, part in ipairs(parts) do
            local pLower = string.lower(part)
            local handled = false

            -- Exact modifier: /exact or /e
            if pLower == "exact" or pLower == "e" then
                exact = true
                handled = true
                hasModifiers = true
            -- Max price modifier: /max=50g
            elseif string.find(pLower, "^max=") then
                local pVal = string.sub(part, 5)
                local copper = SM.ParseMoney(pVal)
                if copper then
                    maxPrice = copper
                    handled = true
                    hasModifiers = true
                end
            -- Quality modifier: /rare, /epic, /q=3
            elseif SM.ParseQuality(part) ~= nil and (pLower ~= "common" or #cleanParts > 0) then
                quality = SM.ParseQuality(part)
                handled = true
                hasModifiers = true
            -- Item level modifier: /ilvl=200-245 or /i200
            elseif
                string.find(pLower, "^ilvl=")
                or (string.len(part) > 1 and string.sub(pLower, 1, 1) == "i" and tonumber(string.sub(part, 2)))
            then
                local minIL, maxIL = SM.ParseItemLevel(part)
                if minIL then
                    minItemLevel = minIL
                    maxItemLevel = maxIL
                    handled = true
                    hasModifiers = true
                end
            -- Character level modifier: /lvl=70-80 or /req=80
            elseif string.find(pLower, "^lvl=") or string.find(pLower, "^req=") then
                local minL, maxL = SM.ParseLevel(part)
                if minL then
                    minLevel = minL
                    maxLevel = maxL
                    handled = true
                    hasModifiers = true
                end
            end

            if not handled and part ~= "" then
                table.insert(cleanParts, part)
            end
        end

        text = table.concat(cleanParts, " ")
    end

    return {
        rawText = rawText,
        cleanSearchText = trim(text),
        exact = exact,
        quality = quality,
        minLevel = minLevel,
        maxLevel = maxLevel,
        minItemLevel = minItemLevel,
        maxItemLevel = maxItemLevel,
        maxPrice = maxPrice,
        hasModifiers = hasModifiers,
    }
end

-- ============================================================================
-- Filter Single Listing against Parsed Modifiers
-- ============================================================================
function SM.FilterListing(listing, filter)
    if not listing or not filter then
        return true
    end

    -- Max price filter (per unit price)
    if filter.maxPrice and filter.maxPrice > 0 then
        local unitPrice = listing.unitPrice
        if not unitPrice and listing.buyoutPrice and listing.stackSize then
            unitPrice = math.floor(listing.buyoutPrice / math.max(1, listing.stackSize))
        end
        if unitPrice and unitPrice > filter.maxPrice then
            return false
        end
    end

    -- Quality filter
    if filter.quality and listing.quality and listing.quality ~= filter.quality then
        return false
    end

    -- Item level filter
    if filter.minItemLevel and listing.ilvl and listing.ilvl < filter.minItemLevel then
        return false
    end
    if filter.maxItemLevel and listing.ilvl and listing.ilvl > filter.maxItemLevel then
        return false
    end

    -- Character requirement level filter
    if filter.minLevel and listing.reqLevel and listing.reqLevel < filter.minLevel then
        return false
    end
    if filter.maxLevel and listing.reqLevel and listing.reqLevel > filter.maxLevel then
        return false
    end

    return true
end

-- ============================================================================
-- Filter Array of Sorted Listings
-- ============================================================================
function SM.FilterSortedData(sortedData, filter)
    if not sortedData or not filter or not filter.hasModifiers then
        return sortedData
    end

    local filtered = {}
    for _, entry in ipairs(sortedData) do
        if SM.FilterListing(entry, filter) then
            table.insert(filtered, entry)
        end
    end
    return filtered
end

-- ============================================================================
-- Global Expose
-- ============================================================================
_G.Atr_ParseSearchModifiers = SM.Parse
_G.Atr_ParseMoneyString = SM.ParseMoney
