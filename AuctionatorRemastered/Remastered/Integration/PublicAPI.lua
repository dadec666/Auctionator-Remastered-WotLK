-- ============================================================================
-- Auctionator Remastered - Public API
-- Official public interface for third-party addons, WeakAuras, macros and scripts.
-- Target: World of Warcraft 3.3.5a (WotLK build 12340)
-- ============================================================================

local addonName, addonTable = ...
local R = AuctionatorRemastered or {}
AuctionatorRemastered = R

R.API = R.API or {}
local API = R.API

-- Version information
API.VERSION = "0.9.0-beta.2"

function API.GetVersion()
    return API.VERSION
end

-- Auction House status
function API.IsOpen()
    return (AuctionFrame and AuctionFrame:IsShown()) or false
end

-- Lowest / current active scan buyout price (in copper)
function API.GetPrice(item)
    if not item then
        return nil
    end
    if Atr_GetAuctionPrice then
        return Atr_GetAuctionPrice(item)
    end
    return nil
end

-- Multi-day historical / reference market price (in copper)
function API.GetMarketPrice(item)
    if not item then
        return nil
    end
    if Atr_DatabaseRecord then
        local record = Atr_DatabaseRecord(item)
        if record and record.marketPrice and record.marketPrice > 0 then
            return record.marketPrice
        end
    end
    return API.GetPrice(item)
end

-- Vendor sell price (in copper)
function API.GetVendorPrice(item)
    if not item then
        return nil
    end
    if Atr_GetSellValue then
        return Atr_GetSellValue(item)
    end
    local sellval = select(11, GetItemInfo(item))
    return sellval or 0
end

-- Disenchant estimated value (in copper)
function API.GetDisenchantPrice(item)
    if not item then
        return nil
    end
    if Atr_GetDisenchantValue then
        return Atr_GetDisenchantValue(item)
    end
    return nil
end

-- Comprehensive stats for an item
function API.GetItemStats(item)
    if not item then
        return nil
    end
    return {
        currentPrice = API.GetPrice(item),
        marketPrice = API.GetMarketPrice(item),
        vendorPrice = API.GetVendorPrice(item),
        disenchantPrice = API.GetDisenchantPrice(item),
    }
end

-- Programmatic Auction House search
function API.Search(query, exact)
    if not query or query == "" then
        return false
    end
    if not API.IsOpen() then
        return false
    end

    local text = query
    if exact and not string.find(text, '^"') then
        text = '"' .. text .. '"'
    end

    -- Modern Buy Terminal search
    if Atr_TriggerBuySearch then
        Atr_TriggerBuySearch(text)
        return true
    end

    -- Fallback to legacy Buy tab search
    if Atr_SetSearchText and Atr_Search_Onclick then
        Atr_SetSearchText(text)
        Atr_Search_Onclick()
        return true
    end

    return false
end

-- Format copper value to readable string
function API.FormatMoney(copper)
    if not copper then
        return "0c"
    end
    local zc = addonTable and addonTable.zc
    if zc and zc.priceToMoneyString then
        return zc.priceToMoneyString(copper)
    end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    return string.format("%dg %ds %dc", g, s, c)
end

-- Expose in global namespace
_G.AuctionatorRemasteredAPI = API
