-- Persistent canonical prices; transient name views keep the inherited engine
-- compatible without storing a second copy of every price/history record.
local DB = {VERSION = 1}
AuctionatorRemastered.Models.Database = DB
local Identity = AuctionatorRemastered.Models.ItemIdentity
local function finite(value) return type(value)=="number" and value==value and value>-math.huge and value<math.huge end
function DB.ValidPrice(value) return finite(value) and value>0 and value<=2147483647 end
local function validName(value) return type(value)=="string" and value~="" and #value<=512 end

local function validRecord(record)
    if type(record)~="table" then return false end
    if record.mr~=nil and not DB.ValidPrice(record.mr) then return false end
    if record.lastScan~=nil and (not finite(record.lastScan) or record.lastScan<=0) then return false end
    for key,value in pairs(record) do
        if type(key)~="string" then return false end
        if key:match("^[HLM]%d+$") and not DB.ValidPrice(value) then return false end
    end
    if record.ms~=nil then
        local samples=record.ms
        if type(samples)~="table" or not finite(samples.day) or samples.day<0 or samples.day~=math.floor(samples.day)
            or type(samples.values)~="table" or #samples.values>24
            or (samples.last~=nil and not finite(samples.last)) then return false end
        for index,value in pairs(samples.values) do
            if type(index)~="number" or index<1 or index>#samples.values or index~=math.floor(index)
                or not DB.ValidPrice(value) then return false end
        end
    end
    return true
end

function DB.New()
    return {schemaVersion=DB.VERSION, markets={},catalog={items={},names={},unresolved={}}}
end

function DB.Clone(root)
    if type(root)~="table" then return nil end
    local copy={schemaVersion=root.schemaVersion or DB.VERSION,markets={},catalog={items={},names={},unresolved={}}}
    if type(root.catalog)=="table" then
        if type(root.catalog.items)=="table" then
            for k,v in pairs(root.catalog.items) do
                if type(v)=="table" then
                    local itemCopy={}
                    for ik,iv in pairs(v) do itemCopy[ik]=iv end
                    copy.catalog.items[k]=itemCopy
                else copy.catalog.items[k]=v end
            end
        end
        if type(root.catalog.names)=="table" then
            for loc,aliases in pairs(root.catalog.names) do
                copy.catalog.names[loc]={}
                if type(aliases)=="table" then for ak,av in pairs(aliases) do copy.catalog.names[loc][ak]=av end end
            end
        end
        if type(root.catalog.unresolved)=="table" then
            for loc,list in pairs(root.catalog.unresolved) do
                copy.catalog.unresolved[loc]={}
                if type(list)=="table" then for uk,uv in pairs(list) do copy.catalog.unresolved[loc][uk]=uv end end
            end
        end
    end
    if type(root.markets)=="table" then
        for scope,m in pairs(root.markets) do
            if type(m)=="table" then
                local marketCopy={items={},names={},unresolved={}}
                if type(m.items)=="table" then
                    for k,rec in pairs(m.items) do
                        if type(rec)=="table" then
                            local recCopy={}
                            for rk,rv in pairs(rec) do
                                if rk=="ms" and type(rv)=="table" then
                                    local msCopy={day=rv.day,last=rv.last,values={}}
                                    if type(rv.values)=="table" then for vi,vv in ipairs(rv.values) do msCopy.values[vi]=vv end end
                                    recCopy.ms=msCopy
                                else recCopy[rk]=rv end
                            end
                            marketCopy.items[k]=recCopy
                        end
                    end
                end
                if type(m.names)=="table" then
                    for loc,aliases in pairs(m.names) do
                        marketCopy.names[loc]={}
                        if type(aliases)=="table" then for ak,av in pairs(aliases) do marketCopy.names[loc][ak]=av end end
                    end
                end
                if type(m.unresolved)=="table" then
                    for loc,unres in pairs(m.unresolved) do
                        marketCopy.unresolved[loc]={}
                        if type(unres)=="table" then
                            for uk,rec in pairs(unres) do
                                if type(rec)=="table" then
                                    local recCopy={}
                                    for rk,rv in pairs(rec) do recCopy[rk]=rv end
                                    marketCopy.unresolved[loc][uk]=recCopy
                                end
                            end
                        end
                    end
                end
                copy.markets[scope]=marketCopy
            end
        end
    end
    return copy
end

function DB.Validate(root)
    if type(root)~="table" or root.schemaVersion~=DB.VERSION then return false,"Unsupported Remastered database version" end
    if type(root.markets)~="table" then return false,"Invalid Remastered market database" end
    local metadata=AuctionatorRemastered.Models.ItemMetadata
    if root.catalog~=nil and metadata and not metadata.Validate(root.catalog) then return false,"Invalid item metadata catalog" end
    for scope,market in pairs(root.markets) do
        if type(scope)~="string" or type(market)~="table" or type(market.items)~="table"
            or type(market.names)~="table" or type(market.unresolved)~="table" then
            return false,"Invalid saved market: "..tostring(scope)
        end
        for key,record in pairs(market.items) do
            if Identity.Parse(key)~=key or not validRecord(record)
                or (record.id~=nil and Identity.Parse(record.id)~=key) then return false,"Invalid item record: "..tostring(key) end
        end
        for locale, aliases in pairs(market.names) do
            if type(locale)~="string" or type(aliases)~="table" then return false,"Invalid name index" end
            for name,key in pairs(aliases) do
                if not validName(name) or (key~=false and (type(key)~="string" or not market.items[key])) then
                    return false,"Invalid item alias"
                end
            end
        end
        for locale,rows in pairs(market.unresolved) do
            if type(locale)~="string" or type(rows)~="table" then return false,"Invalid unresolved item group" end
            for name,row in pairs(rows) do
                if not validName(name) or not validRecord(row) then return false,"Invalid unresolved item" end
            end
        end
    end
    return true
end

function DB.Open(root, scope, locale)
    local ok,reason=DB.Validate(root)
    if not ok then return nil,reason end
    if not validName(scope) or not validName(locale) then return nil,"Invalid market scope or locale" end
    local market=root.markets[scope]
    if not market then
        market={items={},names={},unresolved={}}
        root.markets[scope]=market
    end
    market.names[locale]=market.names[locale] or {}
    market.unresolved[locale]=market.unresolved[locale] or {}
    local handle={root=root,market=market,scope=scope,locale=locale,view={},revision=0,cache={},cacheHits=0,cacheMisses=0}
    local aliases=market.names[locale]
    for name,key in pairs(aliases) do if key then handle.view[name]=market.items[key] end end
    for name,record in pairs(market.unresolved[locale]) do if aliases[name]==nil then handle.view[name]=record end end
    return handle
end

function DB.Touch(handle)
    if handle.deferInvalidation then return end
    handle.revision=handle.revision+1
    handle.cache={}
end

function DB.RefreshView(handle)
    for name in pairs(handle.view) do handle.view[name]=nil end
    local aliases=handle.market.names[handle.locale] or {}
    for name,key in pairs(aliases) do if key then handle.view[name]=handle.market.items[key] end end
    for name,record in pairs(handle.market.unresolved[handle.locale] or {}) do
        if aliases[name]==nil then handle.view[name]=record end
    end
    DB.Touch(handle)
end

function DB.Find(handle, value)
    local key=Identity.Parse(value)
    if key then return handle.market.items[key],key end
    if not validName(value) then return nil end
    local catalog=handle.root.catalog
    local metadataNames=catalog and catalog.names and catalog.names[handle.locale]
    if handle.market.names[handle.locale][value]==false or (metadataNames and metadataNames[value]==false) then return nil,"ambiguous" end
    return handle.view[value],handle.market.names[handle.locale][value]
end

function DB.Bind(handle,name,identity)
    local key=Identity.Parse(identity)
    if not validName(name) or not key then return nil,"Invalid item identity" end
    local market,locale=handle.market,handle.locale
    local aliases,unknown=market.names[locale],market.unresolved[locale]
    local previous=aliases[name]
    local record=market.items[key]
    local changed=not record or record.id~=Identity.Legacy(key)
    if not record then record={};market.items[key]=record end
    -- Unidentified history is not merged into an ID merely because its name matches.
    -- A new identified observation can replace the visible unresolved row safely.
    record.id=Identity.Legacy(key)
    record._name=record._name or name
    if previous==false or (previous and previous~=key) then
        -- A name shared by multiple IDs must never select an arbitrary price.
        changed=changed or previous~=false
        aliases[name]=false;handle.view[name]=nil
    else
        changed=changed or previous~=key or handle.view[name]~=record
        aliases[name]=key;handle.view[name]=record
    end
    if changed then DB.Touch(handle) end
    return record,key
end

function DB.Rows(handle)
    local names=DB.Memo(handle,"displayNames",function()
        local result={}
        for name,key in pairs(handle.market.names[handle.locale]) do
            if key and (not result[key] or name<result[key]) then result[key]=name end
        end
        return result
    end)
    local key,unresolvedKey
    local canonical=true
    return function()
        if canonical then
            local record
            key,record=next(handle.market.items,key)
            if key then return names[key] or record._name or key,record,key end
            canonical=false
        end
        local unknown=handle.market.unresolved[handle.locale]
        while true do
            local record
            unresolvedKey,record=next(unknown,unresolvedKey)
            if not unresolvedKey then return nil end
            if handle.market.names[handle.locale][unresolvedKey]==nil then return unresolvedKey,record,nil end
        end
    end
end

function DB.Write(handle,name,price,stamp,day,identity)
    if not validName(name) or not DB.ValidPrice(price) or not finite(stamp) or stamp<=0
        or not finite(day) or day<0 or day~=math.floor(day) then return nil,"Invalid price observation" end
    local record,key
    if identity then record,key=DB.Bind(handle,name,identity)
    elseif identity~=false then record,key=DB.Find(handle,name) end
    if not record then
        if key=="ambiguous" or identity then return nil,key or "Invalid item identity" end
        record=handle.market.unresolved[handle.locale][name] or {}
        handle.market.unresolved[handle.locale][name]=record
        if handle.market.names[handle.locale][name]==nil then handle.view[name]=record end
    end
    if identity then handle.market.unresolved[handle.locale][name]=nil end
    record.mr,record.lastScan=price,stamp
    local high,low="H"..day,"L"..day
    local previousHigh=record[high]
    local previousLow=record[low] or previousHigh
    local highest=math.max(DB.ValidPrice(previousHigh) and previousHigh or price,price)
    local lowest=math.min(DB.ValidPrice(previousLow) and previousLow or price,price)
    record[high]=highest
    record[low]=lowest<highest and lowest or nil
    record.po=nil
    DB.Touch(handle)
    return record,key
end

-- Apply deliberate removals/replacements made by legacy Clear/Undo/pruning.
-- This is a boundary operation, never performed for every auction row.
function DB.SyncView(handle)
    local market,locale=handle.market,handle.locale
    local aliases,unknown=market.names[locale],market.unresolved[locale]
    local live, removed = {}, {}
    for name,key in pairs(aliases) do
        if key then
            local record=handle.view[name]
            if record then market.items[key]=record;live[key]=true
            else aliases[name]=nil;removed[key]=true end
        end
    end
    for key in pairs(removed) do
        if not live[key] then
            market.items[key]=nil
            for _,other in pairs(market.names) do
                for alias,id in pairs(other) do if id==key then other[alias]=nil end end
            end
        end
    end
    for name in pairs(unknown) do if not handle.view[name] then unknown[name]=nil end end
    for name,record in pairs(handle.view) do
        if type(record)=="table" then
            local key=aliases[name]
            if key then market.items[key]=record
            elseif aliases[name]~=false then
                local identity=Identity.Parse(record.id)
                if identity then market.items[identity]=record;aliases[name]=identity
                else unknown[name]=record end
            end
        end
    end
    DB.Touch(handle)
end

function DB.Clear(handle)
    local market=handle.market
    local backup={items=market.items,names=market.names,unresolved=market.unresolved,
        lastScan=market.lastScan,lastCompleteScan=market.lastCompleteScan}
    market.items,market.names,market.unresolved={},{[handle.locale]={}},{[handle.locale]={}}
    market.lastScan,market.lastCompleteScan=nil,nil
    DB.RefreshView(handle)
    return backup
end

function DB.Restore(handle,backup)
    local market=handle.market
    for key,record in pairs(backup.items) do if market.items[key]==nil then market.items[key]=record end end
    for locale,aliases in pairs(backup.names) do
        market.names[locale]=market.names[locale] or {}
        for name,key in pairs(aliases) do
            local current=market.names[locale][name]
            if current==nil then market.names[locale][name]=key
            elseif current~=key then market.names[locale][name]=false end
        end
    end
    for locale,rows in pairs(backup.unresolved) do
        market.unresolved[locale]=market.unresolved[locale] or {}
        for name,record in pairs(rows) do
            if market.unresolved[locale][name]==nil then market.unresolved[locale][name]=record end
        end
    end
    market.lastScan=market.lastScan or backup.lastScan
    market.lastCompleteScan=market.lastCompleteScan or backup.lastCompleteScan
    DB.RefreshView(handle)
end

function DB.Memo(handle, key, build)
    local saved=handle.cache[key]
    if saved~=nil then handle.cacheHits=handle.cacheHits+1;return saved end
    handle.cacheMisses=handle.cacheMisses+1
    local value=build()
    handle.cache[key]=value
    return value
end

-- Prune in place: preserve live references and avoid a full database deep copy.
function DB.Prune(handle,today,historyDays,itemDays)
    local cutoff,oldest=today-historyDays,today-itemDays
    local function retain(record)
        local newest=-1
        for key,value in pairs(record) do
            if type(key)=="string" and key:sub(1,1)=="H" and DB.ValidPrice(value) then
                local day=tonumber(key:sub(2))
                if day then newest=math.max(newest,day) end
            end
        end
        if newest~=-1 and newest<oldest then return false end
        for key in pairs(record) do
            if type(key)=="string" then
                local kind=key:sub(1,1)
                if kind=="H" or kind=="L" then
                    local day=tonumber(key:sub(2))
                    if day and day<cutoff and day~=newest then record[key]=nil end
                elseif kind=="M" then
                    local day=tonumber(key:sub(2))
                    if day and (day<today-30 or day>today) then record[key]=nil end
                end
            end
        end
        if type(record.ms)=="table" and record.ms.day~=today then record.ms=nil end
        return true
    end
    for key,record in pairs(handle.market.items) do
        if not retain(record) then
            handle.market.items[key]=nil
            for _,aliases in pairs(handle.market.names) do
                for name,id in pairs(aliases) do if id==key then aliases[name]=nil end end
            end
        end
    end
    for _,rows in pairs(handle.market.unresolved) do
        for name,record in pairs(rows) do if not retain(record) then rows[name]=nil end end
    end
    for name in pairs(handle.view) do handle.view[name]=nil end
    local aliases=handle.market.names[handle.locale]
    for name,key in pairs(aliases) do if key then handle.view[name]=handle.market.items[key] end end
    for name,record in pairs(handle.market.unresolved[handle.locale]) do
        if aliases[name]==nil then handle.view[name]=record end
    end
    DB.Touch(handle)
end
