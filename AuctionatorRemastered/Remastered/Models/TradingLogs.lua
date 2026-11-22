-- Unified view of the existing purchase, posting and sales ledgers. No trading actions.
local function scope(root)
    local key = GetRealmName().."_"..UnitFactionGroup("player")
    return type(root) == "table" and root[key] and root[key].records or {}
end

function Atr_GetTradingLogs(kind, query, days, character)
    local result, spent, listed, boughtItems, listedItems, earned, soldItems = {}, 0, 0, 0, 0, 0, 0
    query = string.lower(query or "")
    local cutoff = days and time() - days * 86400 or 0
    local function collect(records, recordKind)
        if kind ~= "All" and kind ~= recordKind then return end
        for _, record in ipairs(records) do
            if record.when >= cutoff and (not character or record.character == character)
                and (query == "" or string.find(string.lower(record.name), query, 1, true)) then
                local stacks = record.stacks or 1
                local size = record.stackSize or 1
                local quantity = size * stacks
                local total = record.stackPrice * stacks
                result[#result + 1] = {
                    kind = recordKind, name = record.name, link = record.link, itemKey=record.itemKey,
                    quantity = quantity, unit = record.stackPrice / size,
                    total = total, when = record.when, character = record.character,
                    seller = record.seller, buyer = record.buyer, stacks = stacks, size = size,
                    deposit = record.deposit, consignment = record.consignment, net = record.net,
                }
                if recordKind == "Bought" then
                    spent = spent + total
                    boughtItems = boughtItems + quantity
                elseif recordKind == "Listed" then
                    listed = listed + total
                    listedItems = listedItems + quantity
                elseif recordKind == "Sold" then
                    earned = earned + total
                    soldItems = soldItems + quantity
                end
            end
        end
    end
    collect(scope(AUCTIONATOR_PURCHASES), "Bought")
    collect(scope(AUCTIONATOR_OWN_AUCTIONS), "Listed")
    collect(scope(AUCTIONATOR_SALES), "Sold")
    table.sort(result, function(a,b)
        if a.when == b.when then return a.name < b.name end
        return a.when > b.when
    end)
    return result, spent, listed, boughtItems, listedItems, earned, soldItems
end

-- Sort display rows only; persistent ledgers and filtered totals are untouched.
function Atr_SortTradingLogs(records, key, descending)
    local numeric={quantity=true,unit=true,total=true,when=true}
    local allowed={kind=true,name=true,quantity=true,unit=true,total=true,character=true,when=true}
    if not allowed[key] then key='when' end
    local order={}
    for i,row in ipairs(records) do order[row]=i end
    table.sort(records,function(a,b)
        local av,bv=a[key],b[key]
        if numeric[key] then av,bv=tonumber(av) or 0,tonumber(bv) or 0
        else av,bv=string.lower(tostring(av or '')),string.lower(tostring(bv or '')) end
        if av==bv then return order[a]<order[b] end
        if descending then return av>bv end
        return av<bv
    end)
    return records
end

