-- Sole bridge between persisted ID-keyed prices and the inherited name-based
-- engine. Legacy price/history tables are transient views, never serialized.
local R=AuctionatorRemastered
local DB,Identity=R.Models.Database,R.Models.ItemIdentity
local Service={}
R.Database=Service
local handles,legacyRoot={},nil
local batch
local sampleView,sampleName={},nil
local function scope() return GetRealmName().."_"..UnitFactionGroup("player") end
local function locale() return GetLocale and GetLocale() or "enUS" end
local function now() return time() end

local function sample(handle,name,price,record)
    if sampleName then sampleView[sampleName]=nil end
    sampleName=name;sampleView[name]=record
    Atr_RecordMarketObservation(name,price,sampleView)
end

function Service.Open()
    if Service.failed then return nil end
    if AUCTIONATOR_REMASTERED_DATABASE==nil then AUCTIONATOR_REMASTERED_DATABASE=DB.New() end
    local key=scope()
    local handle,reason=DB.Open(AUCTIONATOR_REMASTERED_DATABASE,key,locale())
    if not handle and reason~="Unsupported Remastered database version" then
        if type(AUCTIONATOR_REMASTERED_DATABASE_BAK)=="table"
            and AUCTIONATOR_REMASTERED_DATABASE_BAK.schemaVersion==DB.VERSION
            and DB.Validate(AUCTIONATOR_REMASTERED_DATABASE_BAK) then
            AUCTIONATOR_REMASTERED_DATABASE=DB.Clone(AUCTIONATOR_REMASTERED_DATABASE_BAK)
            handle,reason=DB.Open(AUCTIONATOR_REMASTERED_DATABASE,key,locale())
            if handle and DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
                DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Auctionator Remastered|r: Price database restored from backup after corruption.")
            end
        end
    end
    if not handle then Service.failed=reason;return nil,reason end
    Service.active=handle;handles[handle.view]=handle
    legacyRoot=legacyRoot or {__dbversion=4}
    legacyRoot[key]=handle.view
    AUCTIONATOR_PRICE_DATABASE=legacyRoot
    gAtr_ScanDB=handle.view
    return handle
end

function Atr_DatabaseInitialize()
    local handle=Service.active
    if not handle or handle.scope~=scope() then handle=Service.Open() end
    if not handle then return false end
    AUCTIONATOR_PRICE_DATABASE=legacyRoot;gAtr_ScanDB=handle.view
    if not AUCTIONATOR_MARKET_HISTORY_UPGRADED then
        AUCTIONATOR_DB_MAXHIST_DAYS=math.max(30,tonumber(AUCTIONATOR_DB_MAXHIST_DAYS) or 30)
        AUCTIONATOR_MARKET_HISTORY_UPGRADED=true
    end
    Atr_PruneScanDB()
    Atr_PrunePostDB()
    Atr_DatabaseBackup()
    Atr_Broadcast_DBupdated(0,"dbinited")
    return true
end

function Atr_DatabaseHandles(database)
    return not Service.failed and Service.active~=nil and (database==nil or handles[database]~=nil)
end

function Atr_DatabaseRecord(value,database)
    local handle=database and handles[database] or Service.active
    if not handle then return nil end
    return DB.Find(handle,value)
end

function Atr_DatabaseRows(database)
    local handle=database and handles[database] or Service.active
    if handle then return DB.Rows(handle) end
    local key
    return function()
        local record
        key,record=next(database or {},key)
        return key,record
    end
end

function Atr_DatabaseBindItem(name,link)
    local handle=Service.active
    if not handle or not Identity.LinkMatchesName(link,name) then return nil end
    return DB.Bind(handle,name,link)
end

function Atr_DatabaseWritePrice(name,price,database,identity)
    local handle=database and handles[database] or Service.active
    if not handle then return nil end
    if batch and handle==Service.active then return nil end -- commit staged variants once
    local record,key=DB.Write(handle,name,price,now(),Atr_GetScanDay_Today(),identity)
    if record then record._source="search";record._partial=nil;sample(handle,name,price,record) end
    return record,key
end

function Atr_DatabaseClearAll()
    local root=AUCTIONATOR_REMASTERED_DATABASE
    if not root or Service.failed then return false end
    root.markets={};handles={};legacyRoot=nil;Service.active=nil
    return Atr_DatabaseInitialize()
end

function Atr_DatabaseSync()
    if Service.active then DB.SyncView(Service.active) end
end

function Atr_DatabaseClearMarket()
    if Service.active then return DB.Clear(Service.active) end
end

function Atr_DatabaseUndoMarket(snapshot)
    if Service.active and snapshot then DB.Restore(Service.active,snapshot) end
end

function Atr_DatabasePrune()
    local handle=Service.active
    if not handle then return false end
    local history=tonumber(AUCTIONATOR_DB_MAXHIST_DAYS) or 30
    local age=tonumber(AUCTIONATOR_DB_MAXITEM_AGE) or 180
    DB.Prune(handle,Atr_GetScanDay_Today(),math.max(1,math.min(3650,history)),math.max(1,math.min(3650,age)))
    return true
end

function Atr_DatabaseMemo(database,key,build)
    local handle=database and handles[database] or Service.active
    if not handle or Service.failed then return build() end
    local day,window=Atr_GetScanDay_Today(),Atr_GetMarketHistoryDays()
    if handle.cacheDay~=day or handle.cacheWindow~=window then
        handle.cache={};handle.cacheDay=day;handle.cacheWindow=window
    end
    return DB.Memo(handle,key,build)
end

function Atr_DatabaseBeginFullScan()
    batch={rows={},unknown={},invalid=0,started=now()}
end

function Atr_DatabaseObserveRow(name,link,count,buyout,quality)
    if not batch then return end
    if type(name)~="string" or name=="" or not DB.ValidPrice(count) or count~=math.floor(count)
        or type(quality)~="number" or quality<0 or quality>7 or quality~=math.floor(quality) then
        batch.invalid=batch.invalid+1;return
    end
    if buyout==nil or buyout==0 then return end -- valid bid-only listings have no price observation
    if not DB.ValidPrice(buyout) then batch.invalid=batch.invalid+1;return end
    local price=math.floor(buyout/count)
    if not DB.ValidPrice(price) then return end
    local key=Identity.LinkMatchesName(link,name) and Identity.Parse(link) or nil
    local collection,id=key and batch.rows or batch.unknown,key or name
    local entry=collection[id]
    if not entry then entry={name=name,price=price,quality=quality,key=key,names={}};collection[id]=entry end
    entry.price=math.min(entry.price,price);entry.names[name]=true
end

-- Prepare expensive history work off to the side. Only publish once every
-- observation is prepared; cancellation never exposes half a scan's prices.
function Atr_DatabaseCancelFullScan()
    batch=nil
end

function Atr_DatabasePrepareFullScan(scanned,complete,slow)
    local handle,staged=Service.active,batch
    if not handle or not staged then return nil end
    local locale=handle.locale
    local market={items={},names={[locale]={}},unresolved={[locale]={}}}
    staged.work={root=handle.root,market=market,locale=locale,view={},revision=0,cache={},deferInvalidation=true}
    staged.handle=handle;staged.stamp=now();staged.day=Atr_GetScanDay_Today()
    staged.minimum=tonumber(AUCTIONATOR_SCAN_MINLEVEL) or 1
    staged.summary={started=staged.started,finished=staged.stamp,complete=complete==true and staged.invalid==0,
        mode=slow and "slow" or "fast",auctions=scanned,identified=0,unresolved=0,invalid=staged.invalid,
        added=0,updated=0,ignored=0,totalItems=0,numEachQual={0,0,0,0,0,0,0,0,0},numRemoved={0,0,0,0,0,0,0,0}}
    staged.phase="rows";staged.cursor=nil
    return staged.summary
end

local function copyRecord(record)
    local result={}
    for k,v in pairs(record or {}) do
        if k=="ms" then
            local ms={};for field,value in pairs(v) do ms[field]=value end
            ms.values={};for i,value in ipairs(v.values) do ms.values[i]=value end
            result[k]=ms
        else result[k]=v end
    end
    return result
end

function Atr_DatabaseFullScanStep(budget)
    local staged=batch
    if not staged or not staged.work then return true,nil end
    local handle,work,summary=staged.handle,staged.work,staged.summary
    if handle~=Service.active then batch=nil;return true,nil end
    local start=GetTime()
    for _=1,256 do
        local collection=staged.phase=="rows" and staged.rows or staged.unknown
        local key,entry=next(collection,staged.cursor)
        if not key then
            if staged.phase=="rows" then staged.phase="unknown";staged.cursor=nil
            else
                -- Publish prepared records/aliases without calling price/history
                -- writers again. This short, non-yielding boundary is atomic.
                local market,locale=handle.market,handle.locale
                for id,record in pairs(work.market.items) do market.items[id]=record end
                for name,record in pairs(work.market.unresolved[locale]) do market.unresolved[locale][name]=record end
                for name,id in pairs(work.market.names[locale]) do
                    market.names[locale][name]=id
                    if id then market.unresolved[locale][name]=nil end
                end
                summary.finished=now()
                market.lastScan=summary
                if summary.complete then market.lastCompleteScan=summary.finished end
                DB.RefreshView(handle)
                batch=nil
                return true,summary
            end
        else
            staged.cursor=key
            local qx=entry.quality+1
            summary.totalItems=summary.totalItems+1;summary.numEachQual[qx]=summary.numEachQual[qx]+1
            if qx<staged.minimum then summary.ignored=summary.ignored+1
            else
                local locale=handle.locale
                for name in pairs(entry.names) do
                    if work.market.names[locale][name]==nil then
                        work.market.names[locale][name]=handle.market.names[locale][name]
                    end
                end
                local old=entry.key and handle.market.items[entry.key] or handle.market.unresolved[locale][entry.name]
                if entry.key then work.market.items[entry.key]=copyRecord(old)
                else work.market.unresolved[locale][entry.name]=copyRecord(old) end
                local record=DB.Write(work,entry.name,entry.price,staged.stamp,staged.day,entry.key or false)
                if record then
                    record._source="fullscan";record.quality=entry.quality;record._partial=not summary.complete or nil
                    if entry.key then
                        for name in pairs(entry.names) do DB.Bind(work,name,entry.key) end
                        summary.identified=summary.identified+1
                    else summary.unresolved=summary.unresolved+1 end
                    sample(work,entry.name,entry.price,record)
                    local kind=old and DB.ValidPrice(old.mr) and "updated" or "added"
                    summary[kind]=summary[kind]+1
                else summary.invalid=summary.invalid+1;summary.complete=false end
            end
        end
        if GetTime()-start>=(budget or .003) then break end
    end
    return false,summary
end

-- Synchronous boundary retained for non-UI callers; live scans use bounded steps.
function Atr_DatabaseCommitFullScan(scanned,complete,slow)
    if not Atr_DatabasePrepareFullScan(scanned,complete,slow) then return end
    local done,summary
    repeat done,summary=Atr_DatabaseFullScanStep() until done
    return summary
end

-- Validate after SavedVariables have loaded, before any original initialization.
local originalLoad=Atr_OnLoad
function Atr_OnLoad(...)
    if Service.initialized then return true end
    if Service.initializing or Service.initializationError then return false end
    local handle,reason=Service.Open()
    if not handle then
        if Atr_core then Atr_core:UnregisterAllEvents() end
        StaticPopupDialogs.ATR_DATABASE_UNSUPPORTED={text="Auctionator Remastered could not open its database.\n\n%s\n\nYour saved data has not been reset. Close WoW and restore a supported backup or addon version.",
            button1="Close",timeout=0,whileDead=true,hideOnEscape=true}
        StaticPopup_Show("ATR_DATABASE_UNSUPPORTED",reason or Service.failed)
        return false
    end
    Service.initializing=true
    local result={pcall(originalLoad,...)}
    Service.initializing=nil
    if not result[1] then
        AuctionatorLoaded=false
        Service.initializationError=result[2]
        error(result[2],0)
    end
    Service.initialized=true
    return true
end

function Atr_DatabaseBackup()
    if AUCTIONATOR_REMASTERED_DATABASE and not Service.failed and DB.Validate(AUCTIONATOR_REMASTERED_DATABASE) then
        AUCTIONATOR_REMASTERED_DATABASE_BAK = DB.Clone(AUCTIONATOR_REMASTERED_DATABASE)
    end
end

local events=CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("AUCTION_HOUSE_CLOSED")
events:SetScript("OnEvent",function(_,event)
    if event=="AUCTION_HOUSE_CLOSED" then batch=nil
    elseif event=="PLAYER_LOGOUT" then
        if Service.active then DB.SyncView(Service.active) end
        Atr_DatabaseBackup()
    elseif Service.active then DB.SyncView(Service.active) end
end)

R.Legacy.Hook("Atr_PurgeObsoleteItems",Atr_DatabaseSync)
function Atr_DatabaseInvalidate()
    if Service.active then DB.Touch(Service.active) end
end

function Atr_GetDatabaseHealth()
    local handle=Service.active
    if not handle then return nil,Service.failed end
    local identified,unknown,ambiguous=0,0,0
    for _,record in pairs(handle.market.items) do if DB.ValidPrice(record.mr) then identified=identified+1 end end
    for _,record in pairs(handle.market.unresolved[handle.locale]) do if DB.ValidPrice(record.mr) then unknown=unknown+1 end end
    for _,key in pairs(handle.market.names[handle.locale]) do if key==false then ambiguous=ambiguous+1 end end
    return {schemaVersion=DB.VERSION,identified=identified,unresolved=unknown,ambiguous=ambiguous,
        cacheHits=handle.cacheHits,cacheMisses=handle.cacheMisses,lastCompleteScan=handle.market.lastCompleteScan,
        lastScan=handle.market.lastScan,scope=handle.scope}
end
