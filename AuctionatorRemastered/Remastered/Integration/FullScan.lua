-- Full-scan lifecycle. Own the returned AH buffer until analysis is finished;
-- request pacing is separate from the CPU budget used to consume that buffer.
local R=AuctionatorRemastered
local S={budget=.003,maxRows=1000,timeout=30,maxRetries=2}
R.FullScan=S
ATR_FS_NULL=0;ATR_FS_STARTED=1;ATR_FS_SLOW_QUERY_SENT=2
ATR_FS_SLOW_QUERY_NEEDED=3;ATR_FS_ANALYZING=4;ATR_FS_UPDATING_DB=5;ATR_FS_CLEANING_UP=6
gAtr_FullScanState=ATR_FS_NULL
local driver=CreateFrame("Frame")
driver:Hide()
local function slowChoice() return Atr_FullScanSlowMode==true or IsControlKeyDown() end
local function status(text)
    if Atr_FullScanStatus:GetText()~=text then Atr_FullScanStatus:SetText(text) end
end
-- Presentation has its own cadence; it never throttles scan processing.
function S.LayoutProgress(active)
    if not S.progress then return end
    Atr_FullScanStatus:ClearAllPoints()
    Atr_FullScanStatus:SetPoint("TOPLEFT",Atr_FullScanFrame,"TOPLEFT",20,active and -160 or -222)
    Atr_FullScanStatus:SetWidth(460);Atr_FullScanStatus:SetHeight(44)
    Atr_FullScanStatus:SetJustifyH("LEFT");Atr_FullScanStatus:SetJustifyV("TOP")
    if Atr_FullScanStatus.SetWordWrap then Atr_FullScanStatus:SetWordWrap(true) end
    if active then
        Atr_FullScanHTML:Hide()
        if not S.hiddenControls then
            S.hiddenControls={}
            for _,name in ipairs({"Atr_FullScanStartButton","Atr_ClearDBButton","Atr_UndoClearDBButton","Atr_SlowScanChoice","Atr_FullScanDone"}) do
                local control=_G[name]
                if control then
                    S.hiddenControls[#S.hiddenControls+1]={control=control,shown=control:IsShown()}
                    control:Hide()
                end
            end
        end
        S.progress:Show();S.timing:Show();S.help:Show()
        S.help:SetText(S.slow and "Cancel scan lets you save completed pages or discard this scan.\nLeaving the auction house discards unsaved prices."
            or "Cancel scan lets you save collected prices or discard this scan.\nLeaving the auction house discards unsaved prices.")
        if S.slow then S.remaining:Show() else S.remaining:Hide() end
    else
        for _,saved in ipairs(S.hiddenControls or {}) do if saved.shown then saved.control:Show() end end
        S.hiddenControls=nil
        S.progress:Hide();S.timing:Hide();S.remaining:Hide();S.help:Hide()
        Atr_FullScanHTML:ClearAllPoints()
        Atr_FullScanHTML:SetPoint("TOPLEFT",Atr_FullScanFrame,"TOPLEFT",20,-270)
        Atr_FullScanHTML:SetHeight(80)
        -- Completion shows its result panel; cancellation returns to help.
        if not Atr_FullScanResults:IsShown() then Atr_FullScanHTML:Show() end
    end
end
local function slowStatus()
    local pages=S.total and math.max(1,math.ceil(S.total/50))
    return pages and string.format("Slow scan: page %d / %d",S.page+1,pages)
        or string.format("Slow scan: page %d",S.page+1)
end
local function compact(value,finished)
    if value<1000 then return tostring(value) end
    if finished and value%1000~=0 then return string.format("%.1fk",value/1000) end
    return math.floor(value/1000).."k"
end
function S.EstimatedRemaining()
    local read,total=S.completedScanned or 0,S.total
    if not S.slow or not total or read<250 or not S.startedAt then return nil end
    local elapsed=GetTime()-S.startedAt-(S.pausedFor or 0)
    if elapsed<3 then return nil end
    return math.max(0,(total-read)*elapsed/read)
end
-- Sample the estimate slowly, smooth fluctuations, and keep a ten-second
-- margin around minute boundaries so a page response cannot flip the label.
local function etaText(now)
    local estimate=S.eta
    if not estimate or now-estimate.updated>=5 then
        local remaining=S.EstimatedRemaining()
        if not remaining then return "Estimating..." end
        if not estimate then
            estimate={seconds=remaining,minutes=remaining<60 and 0 or math.ceil(remaining/60)}
            S.eta=estimate
        else
            estimate.seconds=estimate.seconds*.65+remaining*.35
            local minutes=estimate.seconds<60 and 0 or math.ceil(estimate.seconds/60)
            local lower=estimate.minutes==1 and 50 or (estimate.minutes-1)*60-10
            local upper=estimate.minutes==0 and 70 or estimate.minutes*60+10
            if minutes<estimate.minutes and estimate.seconds<lower
                or minutes>estimate.minutes and estimate.seconds>upper then estimate.minutes=minutes end
        end
        estimate.updated=now
    end
    return estimate.minutes==0 and "<1 min left" or string.format("~%d min left",estimate.minutes)
end
local function updateProgress(force)
    if not S.running or not S.progress then return end
    local now=GetTime()
    if not force and S.lastProgress and now-S.lastProgress<.15 then return end
    S.lastProgress=now
    local read,total=tostring(S.scanned),S.total and tostring(S.total) or "?"
    if not S.slow then
        read=compact(S.scanned,S.scanned==S.total)
        total=S.total and compact(S.total,true) or "?"
    end
    S.progress:SetText(string.format("Auctions read: %s / %s",read,total))
    S.timing:SetText("Elapsed time: "..Atr_FullScan_GetDurString())
    if S.slow then
        if gAtr_FullScanState==ATR_FS_UPDATING_DB then S.remaining:SetText("Saving collected prices...")
        else S.remaining:SetText("Estimated time left: "..etaText(now):gsub(" left$","")) end
    end
end
local function reset()
    driver:Hide();S.running=false;S.issuingQuery=false;gAtr_FullScanState=ATR_FS_NULL
    Atr_FullScanDone:Enable()
    if S.cancel then S.cancel:Hide() end
    S.LayoutProgress(false)
    S.pageRows=nil;S.choicePending=false
    if StaticPopup_Hide then StaticPopup_Hide("ATR_STOP_SCAN") end
end
function Atr_FullScanCancel(reason)
    if not S.running then
        if StaticPopup_Hide then StaticPopup_Hide("ATR_STOP_SCAN") end
        return
    end
    Atr_DatabaseCancelFullScan()
    if Atr_BrowserCancelFullScanMetadata then Atr_BrowserCancelFullScanMetadata() end
    reset()
    if collectgarbage then collectgarbage("step", 100) end
    S.error=reason or "Scan cancelled. Saved prices were not changed."
    status(S.error)
end
function Atr_IsSlowFullScanActive() return S.running and gAtr_FullScanState~=ATR_FS_NULL and S.slow or false end
function Atr_FullScan_GetDurString()
    local elapsed=math.max(0,time()-(S.started or time()))
    return string.format("%d:%02d",math.floor(elapsed/60),elapsed%60)
end
function Atr_FullScanMoreDetails()
    local r=S.result
    if not r then return end
    local function color(hex,text) return "|cff"..hex..text.."|r" end
    local function number(value)
        value=tonumber(value) or 0
        return BreakUpLargeNumbers and BreakUpLargeNumbers(value) or tostring(value)
    end
    local mode=r.mode=="slow" and "Slow scan" or "Fast scan"
    local outcome=r.complete and "complete" or r.stopped and "stopped - partial data saved" or "partial data saved"
    local seconds=math.max(0,(r.finished or time())-(r.started or S.started or time()))
    local duration=string.format("%d:%02d",math.floor(seconds/60),seconds%60)
    print(color("ffd100","Auctionator Remastered").." | "..color(r.complete and "1eff00" or "ffcc00",mode.." "..outcome))
    print("  Auctions read: "..color("ffffff",number(r.auctions)).."  |  Time: "..color("ffffff",duration))
    print("  Items: "..color("ffffff",number(r.totalItems or (r.added+r.updated+r.ignored)))
        .."  |  Added: "..color("1eff00",number(r.added))
        .."  |  Updated: "..color("69ccf0",number(r.updated))
        .."  |  Ignored: "..color("9d9d9d",number(r.ignored)))
    local qualities=r.numEachQual or {}
    local labels={"Poor","Common","Uncommon","Rare","Epic","Legendary","Artifact","Heirloom"}
    local colors={"9d9d9d","ffffff","1eff00","0070dd","a335ee","ff8000","e6cc80","e6cc80"}
    local function quality(index) return color(colors[index],number(qualities[index]).." "..labels[index]) end
    print("  Quality: "..quality(1).."  |  "..quality(2))
    local extra={quality(3),quality(4),quality(5)}
    for i=6,8 do if (qualities[i] or 0)>0 then extra[#extra+1]=quality(i) end end
    print("  "..table.concat(extra,"  |  "))
end
local function finish(result)
    if not result then Atr_FullScanCancel("Scan stopped before prices could be saved.");return end
    S.result=result;S.running=false
    reset()
    Atr_FSR_scanned_count:SetText(result.auctions)
    Atr_FSR_added_count:SetText(result.added)
    Atr_FSR_updated_count:SetText(result.updated)
    Atr_FSR_ignored_count:SetText(result.ignored)
    Atr_FullScanHTML:Hide();Atr_FullScanResults:Show()
    status(result.complete and "Scan complete!" or result.stopped and "Scan stopped. Collected prices saved (partial scan)." or "Partial scan saved. Some auction data was missing.")
    Atr_UpdateFullScanFrame()
    -- UI refreshes may change the status; retain the result's actual outcome.
    status(result.complete and "Scan complete!" or result.stopped and "Scan stopped. Collected prices saved (partial scan)." or "Partial scan saved. Some auction data was missing.")
    Atr_FullScanMoreDetails()
    Atr_Broadcast_DBupdated(result.identified+result.unresolved,"fullscan")
    if Atr_DatabaseBackup then Atr_DatabaseBackup() end
    if collectgarbage then collectgarbage("step", 100) end
    -- Empty the client's bulk buffer when possible. Completion never depends
    -- on this optional cleanup request, and no forced full collection is needed.
    if CanSendAuctionQuery() then Atr_ClearBrowseListings() end
end
function Atr_FullScanUpdateDB()
    if not S.running or gAtr_FullScanState==ATR_FS_UPDATING_DB then return end
    if not Atr_DatabasePrepareFullScan(S.scanned,not S.partial,S.slow) then
        Atr_FullScanCancel("Could not prepare scan data. Saved prices were not changed.");return
    end
    gAtr_FullScanState=ATR_FS_UPDATING_DB
    status("Saving scanned prices...")
end
function Atr_FullScanStopAndSave()
    if not S.running then return end
    -- Slow pages enter the database batch only after their final row is read.
    local scanned=S.slow and (S.completedScanned or 0) or S.scanned
    if scanned==0 then
        Atr_FullScanCancel("No completed scan data to save. Previous prices were not changed.")
        return
    end
    S.partial=true;S.scanned=scanned;S.pageRows=nil;S.choicePending=false
    local summary=Atr_DatabasePrepareFullScan(scanned,false,S.slow)
    if not summary then Atr_FullScanCancel();return end
    summary.stopped=true
    gAtr_FullScanState=ATR_FS_UPDATING_DB
    status("Saving collected prices (partial scan)...")
    if StaticPopup_Hide then StaticPopup_Hide("ATR_STOP_SCAN") end
    driver:Show()
end
local function request(...)
    S.issuingQuery=true
    local ok,reason=pcall(QueryAuctionItems,...)
    S.issuingQuery=false
    if not ok then
        Atr_FullScanCancel("Auction query failed. Saved prices were not changed.")
        geterrorhandler()(reason)
    end
    return ok
end
local function readCount()
    local count,total,raw=Atr_GetNumAuctionItems("list")
    if type(count)~="number" or count<0 or count~=math.floor(count) or type(total)~="number" or total<0 then return nil end
    return count,total,raw
end
function Atr_FullScanAnalyze()
    if not S.running then return end
    if gAtr_FullScanState~=ATR_FS_ANALYZING then
        gAtr_FullScanState=ATR_FS_ANALYZING
        S.position=1;S.pageChecked=false;S.pageRows={}
    end
    local count,total,raw=readCount()
    if not count then Atr_FullScanCancel("Invalid auction response. Saved prices were not changed.");return end
    S.total=S.slow and total or count
    if not S.slow and (raw~=total or count~=total) then S.partial=true end
    status(S.slow and slowStatus() or "Reading auctions...")
    if S.expectedCount and not S.slow and S.expectedCount~=count then
        Atr_FullScanCancel("Auction results changed during analysis. Saved prices were not changed.");return
    end
    if not S.slow then S.expectedCount=count end
    if S.slow and count>50 then Atr_FullScanCancel("Unexpected bulk response during slow scan. Saved prices were not changed.");return end
    if S.slow and not S.pageChecked then
        -- Do not stage or count a page twice while retrying missing names.
        local missing=false
        for index=1,count do local name=GetAuctionItemInfo("list",index);if not name or name=="" then missing=true;break end end
        if missing and S.retries<S.maxRetries then
            S.retries=S.retries+1;S.nextQuery=GetTime()+1;S.waitingAt=GetTime()
            gAtr_FullScanState=ATR_FS_SLOW_QUERY_NEEDED
            return
        end
        if missing then S.partial=true end
        S.pageChecked=true
    end
    local started=GetTime()
    local last=math.min(count,S.position+S.maxRows-1)
    for index=S.position,last do
        local name,texture,quantity,quality,_,_,_,_,buyout=GetAuctionItemInfo("list",index)
        local ok,link=pcall(GetAuctionItemLink,"list",index)
        link=ok and link or nil
        if S.slow then
            S.pageRows[#S.pageRows+1]={name=name,link=link,count=quantity,buyout=buyout,quality=quality}
        else Atr_DatabaseObserveRow(name,link,quantity,buyout,quality) end
        if name and name~="" and Atr_BrowserRememberFullScanRow then
            local remembered=pcall(Atr_BrowserRememberFullScanRow,name,texture,quality,index,link)
            if not remembered then S.metadataErrors=(S.metadataErrors or 0)+1 end
        end
        S.scanned=S.scanned+1;S.position=index+1
        if GetTime()-started>=S.budget then break end
    end
    if collectgarbage then collectgarbage("step", 50) end
    updateProgress(S.position>count)
    if S.position<=count then return end
    if S.slow then
        for _,row in ipairs(S.pageRows or {}) do Atr_DatabaseObserveRow(row.name,row.link,row.count,row.buyout,row.quality) end
        S.pageRows=nil;S.completedScanned=S.scanned
        -- Follow the reported total, including exact multiples of 50. An early
        -- empty page is incomplete, never a silently successful truncation.
        if count==0 then
            if S.page*50<total then S.partial=true end
            Atr_FullScanUpdateDB()
        elseif S.page*50+count>=total then Atr_FullScanUpdateDB()
        else
            S.page=S.page+1;S.retries=0;S.nextQuery=GetTime();S.waitingAt=GetTime()
            gAtr_FullScanState=ATR_FS_SLOW_QUERY_NEEDED
        end
    else Atr_FullScanUpdateDB() end
end
local function tick()
    if not S.running then driver:Hide();return end
    if S.choicePending then return end
    local state=gAtr_FullScanState
    if state==ATR_FS_STARTED or state==ATR_FS_SLOW_QUERY_SENT then
        if GetTime()-S.requestedAt>=S.timeout then
            Atr_FullScanCancel("No auction response after 30 seconds. Scan stopped; saved prices were not changed.")
        end
    elseif state==ATR_FS_SLOW_QUERY_NEEDED then
        if GetTime()-S.waitingAt>=S.timeout then
            Atr_FullScanCancel("Auction queries stayed unavailable. Scan stopped; saved prices were not changed.")
        elseif GetTime()>=(S.nextQuery or 0) and CanSendAuctionQuery() then
            gAtr_FullScanState=ATR_FS_SLOW_QUERY_SENT;S.requestedAt=GetTime()
            if not request("",nil,nil,0,0,0,S.page,false,-1) then return end
            status(slowStatus())
        end
    elseif state==ATR_FS_ANALYZING then Atr_FullScanAnalyze()
    elseif state==ATR_FS_UPDATING_DB then
        local done,result=Atr_DatabaseFullScanStep(S.budget)
        if done then finish(result) end
    end
    updateProgress(false)
    if S.running and gAtr_FullScanState~=state and gAtr_FullScanState==ATR_FS_SLOW_QUERY_NEEDED then S.waitingAt=GetTime() end
end
S.Tick=tick
-- Called by the inherited idle loop for routing, never for heavy scan work.
function Atr_FullScanFrameIdle()
    if S.running then return true end
    local slow=slowChoice()
    Atr_FullScanStartButton:SetText(slow and "Start slow scan" or "Start fast scan")
    if slow and CanSendAuctionQuery() then Atr_FullScanStartButton:Enable() end
    return false
end
function Atr_FullScanStart(forceFastScan)
    if S.running or gAtr_FullScanState~=ATR_FS_NULL then return end
    local slow=slowChoice()
    local canQuery,canAll=CanSendAuctionQuery()
    if slow and not canQuery or not slow and not canAll and forceFastScan~=true then return end
    S.slow=slow;S.running=true;S.started=time();S.startedAt=GetTime();S.pausedFor=0;S.pauseStarted=nil;S.scanned=0;S.page=0;S.retries=0
    S.total=nil;S.lastProgress=nil;S.eta=nil;S.completedScanned=0;S.pageRows={};S.choicePending=false
    S.position=1;S.partial=false;S.result=nil;S.error=nil;S.expectedCount=nil;S.metadataErrors=0
    S.waitingAt=GetTime();S.requestedAt=GetTime();S.nextQuery=GetTime()
    Atr_DatabaseBeginFullScan()
    if Atr_BrowserBeginFullScanMetadata then Atr_BrowserBeginFullScanMetadata() end
    SortAuctionClearSort("list")
    Atr_FullScanHTML:Show();Atr_FullScanResults:Hide()
    Atr_FullScanStartButton:Disable();Atr_FullScanDone:Disable()
    if S.cancel then S.cancel:Show() end
    S.LayoutProgress(true);updateProgress(true)
    status(slow and slowStatus() or "Waiting for auction data...")
    if slow then gAtr_FullScanState=ATR_FS_SLOW_QUERY_NEEDED
    else
        gAtr_FullScanState=ATR_FS_STARTED
        -- Cooldown estimates track requests, including interrupted requests;
        -- they never override the client's readiness flag.
        AUCTIONATOR_LAST_SCAN_TIME=time()
        if not request("",nil,nil,0,0,0,0,false,-1,true) then return end
    end
    driver:Show()
end
-- The native event handler changes fast scans to ANALYZING and dispatches
-- slow pages through Atr_FullScanAnalyze. All subsequent work uses this driver.
driver:SetScript("OnUpdate",function()
    local ok,reason=pcall(tick)
    if not ok then
        Atr_FullScanCancel("Scan error. Saved prices were not changed; see Lua errors.")
        geterrorhandler()(reason)
    end
end)
driver:RegisterEvent("AUCTION_HOUSE_CLOSED")
driver:RegisterEvent("PLAYER_LOGOUT")
driver:SetScript("OnEvent",function() Atr_FullScanCancel() end)
local function scanLine(name,y,height,font)
    local line=Atr_FullScanFrame:CreateFontString(name,"OVERLAY",font or "GameFontHighlightSmall")
    line:SetPoint("TOPLEFT",Atr_FullScanFrame,"TOPLEFT",20,y)
    line:SetWidth(460);line:SetHeight(height);line:SetJustifyH("LEFT");line:SetJustifyV("TOP");line:Hide()
    return line
end
S.progress=scanLine("Atr_FullScanProgress",-204,18)
S.timing=scanLine("Atr_FullScanElapsed",-236,18)
S.remaining=scanLine("Atr_FullScanRemaining",-260,18)
S.help=scanLine("Atr_FullScanActiveHelp",-306,40)
S.help:SetTextColor(.65,.65,.65)
local cancel=CreateFrame("Button","Atr_FullScanCancelButton",Atr_FullScanFrame,"UIPanelButtonTemplate")
cancel:SetSize(100,22);cancel:SetPoint("BOTTOMLEFT",Atr_FullScanFrame,"BOTTOMLEFT",20,15)
StaticPopupDialogs.ATR_STOP_SCAN={
    text="Stop this scan?\n\nSave collected prices as a partial scan, or discard them. Unread auctions may contain lower prices.",
    button1="Stop and save",button2="Keep scanning",button3="Discard scan",
    OnAccept=function() Atr_FullScanStopAndSave() end,
    OnAlt=function() Atr_FullScanCancel() end,
    OnHide=function()
        S.choicePending=false
        if S.pauseStarted then S.pausedFor=(S.pausedFor or 0)+GetTime()-S.pauseStarted;S.pauseStarted=nil end
        -- Time spent choosing is not a server-response timeout.
        S.waitingAt=GetTime();S.requestedAt=GetTime()
    end,
    timeout=0,whileDead=true,hideOnEscape=true,
}
cancel:SetText("Cancel scan")
cancel:SetScript("OnClick",function()
    if not S.running then return end
    S.choicePending=true;S.pauseStarted=GetTime();StaticPopup_Show("ATR_STOP_SCAN")
end)
cancel:Hide();S.cancel=cancel
Atr_FullScanFrame:HookScript("OnShow",function()
    if Atr_AnalysisSkin then Atr_AnalysisSkin(cancel,"Button") end
end)

-- Another search replaces the shared list buffer; never mix it into this scan.
hooksecurefunc("QueryAuctionItems",function()
    if S.running and not S.issuingQuery then
        Atr_FullScanCancel("Another auction search interrupted the scan. Saved prices were not changed.")
    end
end)
