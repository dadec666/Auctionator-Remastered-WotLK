-- Market comparison presentation and native Browse sorting.
local marketWindows=AuctionatorRemastered.Models.MarketWindows
local function marketIdentity(name,link)
    return (Atr_DatabaseHandles and Atr_DatabaseHandles() and link) or name
end
local function badge(row, anchor, x)
    if not row.atrMarketPercent then
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetWidth(55); label:SetJustifyH("RIGHT")
        row.atrMarketPercent = label
    end
    local label = row.atrMarketPercent
    label:ClearAllPoints()
    label:SetPoint("RIGHT", anchor, "RIGHT", x, 0)
    label:Show()
    return label
end

-- A compact Buy-only reference summary in the unused upper-right area.
local referencePrice, referenceDetails
local function updateReferenceSummary()
    if not Atr_Main_Panel then return end
    if not referencePrice then
        referencePrice = Atr_Main_Panel:CreateFontString("Atr_MarketReferencePrice", "OVERLAY", "GameFontNormal")
        referenceDetails = Atr_Main_Panel:CreateFontString("Atr_MarketReferenceDetails", "OVERLAY", "GameFontHighlightSmall")
        referencePrice:SetPoint("TOPRIGHT", AuctionFrame, "TOPRIGHT", -25, -91)
        referenceDetails:SetPoint("TOPRIGHT", referencePrice, "BOTTOMRIGHT", 0, -8)
        for _, label in ipairs({referencePrice, referenceDetails}) do
            label:SetWidth(315)
            label:SetJustifyH("RIGHT")
        end
        referenceDetails:SetTextColor(0.75, 0.75, 0.75)
    end
    referencePrice:Hide()
    referenceDetails:Hide()
    if not Atr_Main_Panel:IsShown() or not Atr_IsTabSelected(3) then return end
    local pane = Atr_GetCurrentPane()
    local scan = pane and pane.activeScan
    if not scan or not scan.itemName or scan.itemName == "" or scan.itemName == "nil"
        or not scan.whenScanned or scan.whenScanned <= 0
        or pane:IsScanNil() or Atr_ShowingSearchSummary() then return end
    local price, _, days = Atr_MarketReference(marketIdentity(scan.itemName,scan.itemLink or scan.IDstring))
    if price then
        referencePrice:SetText("Price used for 100%: |cffffffff"..gAtrZC.priceToMoneyString(math.floor(price)).." each|r")
        if days > 0 then
            referenceDetails:SetText("Daily-price median: "..days.." of "..Atr_GetMarketHistoryDays().." days"..(days < 3 and " (preliminary)" or ""))
        else
            referenceDetails:SetText("Preliminary: latest saved low; no prior history.")
        end
    else
        referencePrice:SetText("Price used for 100%: |cffaaaaaaNo price data|r")
        referenceDetails:SetText("Search this item or scan the auction house first.")
    end
    referencePrice:Show()
    referenceDetails:Show()
end

local function updateAuctionator()
    updateReferenceSummary()
    local pane = Atr_GetCurrentPane()
    local scan = pane and pane.activeScan
    for i = 1, 12 do
        local row = _G["AuctionatorEntry"..i]
        if row then
            if row.atrMarketPercent then row.atrMarketPercent:Hide() end
            if scan and Atr_IsSelectedTab_Current() and row:IsShown() then
                local data = scan.sortedData[row:GetID()]
                if data then
                    -- Gap between the per-item money and the auction-count column.
                    local label = badge(row, row, 0)
                    label:ClearAllPoints()
                    label:SetPoint("LEFT", row, "LEFT", 145, 0)
                    label:SetText(Atr_MarketPercentText(marketIdentity(scan.itemName,scan.itemLink or scan.IDstring), data.buyoutPrice, data.stackSize))
                end
            end
        end
    end
end

local function updateBrowse()
    if not AuctionFrameBrowse or not AuctionFrameBrowse:IsShown() then return end
    if Atr_UpdateBrowseMarketControls then Atr_UpdateBrowseMarketControls() end
    local enabled=not Atr_BrowseMarketColumnEnabled or Atr_BrowseMarketColumnEnabled()
    local offset=FauxScrollFrame_GetOffset(BrowseScrollFrame)
    for i=1,(NUM_BROWSE_TO_DISPLAY or 8) do
        local row=_G["BrowseButton"..i]
        local nameText=_G["BrowseButton"..i.."Name"] or _G["BrowseButton"..i.."ItemName"]
        if row and nameText then
            if not row.atrMarketNameWidth then row.atrMarketNameWidth=nameText:GetWidth() end
            nameText:SetWidth(math.max(40,row.atrMarketNameWidth-(enabled and 74 or 0)))
            if row.atrMarketPercent then row.atrMarketPercent:Hide() end
            if enabled and row:IsShown() then
                local index=Atr_GetBrowseMarketIndex and Atr_GetBrowseMarketIndex(offset+i) or offset+i
                local name,_,count,_,_,_,_,_,buyout=GetAuctionItemInfo("list",index)
                if name then
                    local label=badge(row,nameText,0)
                    label:ClearAllPoints();label:SetWidth(68)
                    local level=_G["BrowseButton"..i.."Level"]
                    if level then label:SetPoint("RIGHT",level,"LEFT",-8,0)
                    else label:SetPoint("RIGHT",nameText,"RIGHT",74,0) end
                    label:SetText(Atr_MarketPercentText(marketIdentity(name,GetAuctionItemLink and GetAuctionItemLink("list",index)),buyout,count));label:Show()
                end
            end
        end
    end
end

local function explain(row)
    local name
    if row:GetName() and row:GetName():match("^AuctionatorEntry") then
        if not Atr_IsSelectedTab_Current() then return end
        local pane = Atr_GetCurrentPane()
        local scan=pane and pane.activeScan
        name = scan and marketIdentity(scan.itemName,scan.itemLink or scan.IDstring)
    else
        if Atr_BrowseMarketColumnEnabled and not Atr_BrowseMarketColumnEnabled() then return end
        local index = row:GetID() + FauxScrollFrame_GetOffset(BrowseScrollFrame)
        name = marketIdentity(GetAuctionItemInfo("list", index),GetAuctionItemLink and GetAuctionItemLink("list",index))
    end
    if not name then return end
    local reference, source, days = Atr_MarketReference(name)
    if not reference then return end
    GameTooltip:AddLine("Market %: price per item / reference", 1, 0.82, 0)
    GameTooltip:AddLine("Comparison window: "..Atr_GetMarketHistoryDays().." days (excluding today)", 0.8, 0.8, 0.8)
    GameTooltip:AddLine(source.." ("..(days == 0 and "history building" or days.." days")..")", 0.8, 0.8, 0.8)
    if days < 3 then GameTooltip:AddLine("* Preliminary: fewer than 3 history days.",1,0.82,0) end
    GameTooltip:AddLine("Reference / item: "..gAtrZC.priceToMoneyString(math.floor(reference)), 1, 1, 1)
    GameTooltip:Show()
end

local function attachTips()
    for _, prefix in ipairs({"AuctionatorEntry", "BrowseButton"}) do
        for i = 1, 12 do
            local row = _G[prefix..i]
            if row and not row.atrMarketTipHooked then
                row.atrMarketTipHooked = true
                row:HookScript("OnEnter", explain)
            end
        end
    end
end
AuctionatorRemastered.Legacy.Hook("Atr_ShowCurrentAuctions", function() updateAuctionator(); attachTips() end)
local function hideAuctionatorBadges()
    for i = 1, 12 do
        local row = _G["AuctionatorEntry"..i]
        if row and row.atrMarketPercent then row.atrMarketPercent:Hide() end
    end
end
AuctionatorRemastered.Legacy.Hook("Atr_ShowHistory", hideAuctionatorBadges)
AuctionatorRemastered.Legacy.Hook("Atr_ShowSearchSummary", hideAuctionatorBadges)
-- History/Other reuse Auctionator rows, so remove comparison badges there.
AuctionatorRemastered.Legacy.Hook("Atr_RedisplayAuctions", function() updateAuctionator() end)
local refresh = CreateFrame("Frame")
local elapsedTotal = 0
refresh:SetScript("OnUpdate", function(self, elapsed)
    elapsedTotal = elapsedTotal + elapsed
    if elapsedTotal < 0.3 then return end
    elapsedTotal = 0
    if AuctionFrame and AuctionFrame:IsShown() then updateBrowse(); attachTips(); updateReferenceSummary() end
end)

-- The legacy Scanning options panel is labelled Database in this version.
local options = Atr_ScanningOptionsFrame
local windowLabel = options:CreateFontString(nil, "ARTWORK", "GameFontNormal")
windowLabel:SetPoint("TOPLEFT", options, "TOPLEFT", 30, -275)
windowLabel:SetText(ZT and ZT("Market % comparison:") or "Market % comparison:")
local dropdown = CreateFrame("Frame", "Atr_MarketHistoryDropdown", options, "UIDropDownMenuTemplate")
dropdown:SetPoint("TOPLEFT", options, "TOPLEFT", 215, -265)
UIDropDownMenu_SetWidth(dropdown, 110)
local note = options:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
note:SetPoint("TOPLEFT", options, "TOPLEFT", 30, -310)
note:SetWidth(370); note:SetJustifyH("LEFT")
note:SetText("Median of daily scan medians, excluding today. Older days use daily lows. * = fewer than 3 history days. Changes apply immediately.")
UIDropDownMenu_Initialize(dropdown, function()
    if InCombatLockdown and InCombatLockdown() then return end
    for _, days in ipairs(marketWindows) do
        local selectedDays = days
        local info = UIDropDownMenu_CreateInfo()
        info.text = days.." days"
        info.value = days
        info.checked = Atr_GetMarketHistoryDays() == days
        info.func = function()
            if InCombatLockdown and InCombatLockdown() then return end
            AUCTIONATOR_MARKET_HISTORY_DAYS = selectedDays
            UIDropDownMenu_SetSelectedValue(dropdown, selectedDays)
            updateAuctionator()
            if Atr_RefreshBrowseMarketSort then Atr_RefreshBrowseMarketSort() end
        end
        UIDropDownMenu_AddButton(info)
    end
end)
dropdown:SetScript("OnShow", function()
    if InCombatLockdown and InCombatLockdown() then return end
    UIDropDownMenu_SetSelectedValue(dropdown, Atr_GetMarketHistoryDays())
end)

-- Browse-only presentation sort. Auction indices used by purchases and the scan
-- database stay native. API remapping exists ONLY inside a synchronous redraw.
local browseDirection,browseOrder,renderOrder,renderInverse
local browseHeader,browseCheck
local browseInstalled=false
local function browseConfig()
    if type(AUCTIONATOR_SAVEDVARS)~="table" then AUCTIONATOR_SAVEDVARS={} end
    return AUCTIONATOR_SAVEDVARS
end
function Atr_BrowseMarketColumnEnabled() return browseConfig().browseMarketPercent~=false end
function Atr_GetBrowseMarketIndex(index) return browseOrder and browseOrder[index] or index end
function Atr_BuildBrowseMarketOrder(count,reader,descending,identityReader)
    local entries,order,inverse={},{},{}
    for index=1,count do
        local name,_,quantity,_,_,_,_,_,buyout=reader("list",index)
        entries[#entries+1]={index=index,value=Atr_MarketPercentValue(marketIdentity(name,identityReader and identityReader("list",index)),buyout,quantity)}
    end
    table.sort(entries,function(a,b)
        if a.value==b.value then return a.index<b.index end
        if a.value==nil then return false end
        if b.value==nil then return true end
        if descending then return a.value>b.value end
        return a.value<b.value
    end)
    for visual,entry in ipairs(entries) do order[visual]=entry.index;inverse[entry.index]=visual end
    return order,inverse
end
local function resetBrowseIDs(order)
    local offset=FauxScrollFrame_GetOffset(BrowseScrollFrame)
    for i=1,(NUM_BROWSE_TO_DISPLAY or 8) do
        local row=_G["BrowseButton"..i]
        if row then row:SetID(order and ((order[offset+i] or offset+i)-offset) or i) end
    end
end
local function fullScanActive()
    return gAtr_FullScanState and gAtr_FullScanState~=ATR_FS_NULL
end
local function installBrowseSort()
    if browseInstalled or type(AuctionFrameBrowse_Update)~="function" then return end
    browseInstalled=true
    local nativeUpdate=AuctionFrameBrowse_Update
    local nativeInfo,nativeTime,nativeLink=GetAuctionItemInfo,GetAuctionItemTimeLeft,GetAuctionItemLink
    local nativeSelected=GetSelectedAuctionItem
    GetAuctionItemInfo=function(kind,index,...)
        if kind=="list" and renderOrder then index=renderOrder[index] or index end
        return nativeInfo(kind,index,...)
    end
    GetAuctionItemTimeLeft=function(kind,index,...)
        if kind=="list" and renderOrder then index=renderOrder[index] or index end
        return nativeTime(kind,index,...)
    end
    GetAuctionItemLink=function(kind,index,...)
        if kind=="list" and renderOrder then index=renderOrder[index] or index end
        return nativeLink(kind,index,...)
    end
    GetSelectedAuctionItem=function(kind,...)
        local index=nativeSelected(kind,...)
        if kind=="list" and renderInverse and index then return renderInverse[index] or index end
        return index
    end
    AuctionFrameBrowse_Update=function(...)
        if renderOrder then return end -- do not recurse through another redraw hook
        local inverse
        browseOrder=nil
        local count=GetNumAuctionItems("list") or 0
        if Atr_BrowseMarketColumnEnabled() and browseDirection and AuctionFrameBrowse:IsShown()
            and not fullScanActive() and count<=50 then
            browseOrder,inverse=Atr_BuildBrowseMarketOrder(count,nativeInfo,browseDirection=="high",nativeLink)
        end
        resetBrowseIDs(nil)
        renderOrder,renderInverse=browseOrder,inverse
        local result={pcall(nativeUpdate,...)}
        renderOrder,renderInverse=nil,nil
        -- A row's ID plus the real scroll offset now yields the native auction
        -- index for Blizzard's click, tooltip, dress-up and bid/buyout handlers.
        resetBrowseIDs(browseOrder)
        if not result[1] then error(result[2],0) end
        updateBrowse()
        return unpack(result,2)
    end
    -- AUCTION_ITEM_LIST_UPDATE refreshes native arrows AFTER the row redraw.
    -- Hide the named Arrow texture there too; skins can replace NormalTexture.
    if SortButton_UpdateArrow then
        hooksecurefunc("SortButton_UpdateArrow",function(button,kind)
            if kind=="list" and browseDirection and Atr_BrowseMarketColumnEnabled() then
                local name=button:GetName()
                local arrow=name and _G[name.."Arrow"]
                if arrow then arrow:Hide() end
                local normal=button:GetNormalTexture()
                if normal then normal:Hide() end
            end
        end)
    end
    if AuctionFrame_OnClickSortColumn then
        hooksecurefunc("AuctionFrame_OnClickSortColumn",function()
            -- Switching a native Browse header exits the local presentation sort.
            if AuctionFrameBrowse and AuctionFrameBrowse:IsShown() then
                browseDirection=nil;browseOrder=nil;AuctionFrameBrowse_Update()
            end
        end)
    end
end
function Atr_RefreshBrowseMarketSort()
    if browseInstalled and browseDirection and AuctionFrameBrowse and AuctionFrameBrowse:IsShown() then AuctionFrameBrowse_Update() end
end
function Atr_SetBrowseMarketColumnEnabled(enabled)
    browseConfig().browseMarketPercent=enabled and true or false
    browseDirection=nil;browseOrder=nil
    if browseCheck then browseCheck:SetChecked(Atr_BrowseMarketColumnEnabled()) end
    if browseInstalled then AuctionFrameBrowse_Update() else updateBrowse() end
end
-- Keep the native Rarity column's layout anchors intact: Level is positioned
-- from it. Trim only its mouse/highlight area to reserve Market % space.
local function fitBrowseRarityHeader(enabled)
    local rarity=BrowseQualitySort
    if not rarity then return end
    local texture=rarity:GetHighlightTexture()
    if not rarity.atrMarketHeaderLayout then
        local insets=rarity.GetHitRectInsets and {rarity:GetHitRectInsets()} or {0,0,0,0}
        local points={}
        if texture and texture.GetNumPoints then
            for i=1,texture:GetNumPoints() do points[i]={texture:GetPoint(i)} end
        end
        rarity.atrMarketHeaderLayout={insets=insets,points=points}
    end
    local saved=rarity.atrMarketHeaderLayout
    local trim=enabled and 80 or 0
    if enabled and browseHeader and rarity.GetRight and browseHeader.GetLeft then
        local right,left=rarity:GetRight(),browseHeader:GetLeft()
        if right and left then
            local nativeScale=rarity:GetEffectiveScale()
            trim=math.max(0,(right*nativeScale-left*browseHeader:GetEffectiveScale())/nativeScale+1)
        end
    end
    rarity:SetHitRectInsets(saved.insets[1],saved.insets[2]+trim,saved.insets[3],saved.insets[4])
    -- The vanilla three-piece tab is wider than the trimmed mouse area too.
    -- Its middle stretches between Left and Right, so moving Right also ends
    -- the background before Market %, without moving Level or later columns.
    local right=_G.BrowseQualitySortRight
    if right and not ElvUI then
        if not saved.rightPoints then
            saved.rightPoints={}
            if right.GetNumPoints then
                for i=1,right:GetNumPoints() do saved.rightPoints[i]={right:GetPoint(i)} end
            end
        end
        right:ClearAllPoints()
        if enabled then right:SetPoint("TOPRIGHT",rarity,"TOPRIGHT",-trim,0)
        elseif #saved.rightPoints>0 then
            for _,point in ipairs(saved.rightPoints) do right:SetPoint(unpack(point)) end
        else right:SetPoint("TOPRIGHT",rarity,"TOPRIGHT",0,0) end
    end
    -- ElvUI adds separate pressed/checked overlays. They do not inherit the
    -- hover texture's bounds and must be trimmed independently, including when
    -- the skin creates them after our first layout pass.
    saved.effects=saved.effects or {}
    local seen={}
    if texture then seen[texture]=true end
    for _,effect in pairs({rarity.GetPushedTexture and rarity:GetPushedTexture(),
        rarity.GetCheckedTexture and rarity:GetCheckedTexture(),rarity.pushed,rarity.checked,rarity.hover}) do
        if (type(effect)=="table" or type(effect)=="userdata") and not seen[effect] then
            seen[effect]=true
            if not saved.effects[effect] then
                local points={}
                if effect.GetNumPoints then
                    for i=1,effect:GetNumPoints() do points[i]={effect:GetPoint(i)} end
                end
                saved.effects[effect]=points
            end
            effect:ClearAllPoints()
            if enabled then
                effect:SetPoint("TOPLEFT",rarity,"TOPLEFT",0,0)
                effect:SetPoint("BOTTOMRIGHT",rarity,"BOTTOMRIGHT",-trim,0)
            elseif #saved.effects[effect]>0 then
                for _,point in ipairs(saved.effects[effect]) do effect:SetPoint(unpack(point)) end
            else effect:SetAllPoints(rarity) end
        end
    end
    if texture then
        texture:ClearAllPoints()
        if enabled then
            texture:SetPoint("TOPLEFT",rarity,"TOPLEFT",0,0)
            texture:SetPoint("BOTTOMRIGHT",rarity,"BOTTOMRIGHT",-trim,0)
        elseif #saved.points>0 then
            for _,point in ipairs(saved.points) do texture:SetPoint(unpack(point)) end
        else texture:SetAllPoints(rarity) end
    end
end
local function styleBrowseMarketHeader()
    local native=BrowseQualitySort
    if not browseHeader or not native then return end
    browseHeader:SetNormalFontObject(native.GetNormalFontObject and native:GetNormalFontObject() or GameFontHighlightSmall)
    browseHeader:SetHighlightFontObject(native.GetHighlightFontObject and native:GetHighlightFontObject() or GameFontHighlightSmall)
    -- ElvUI's native sort headers use Toolkit.StyleButton's color texture.
    -- Build that exact highlight directly, even if the older skin callback
    -- stopped before assigning StyleButton/hover to the reference button.
    if ElvUI then
        -- AuctionSortButtonTemplate supplies a three-piece vanilla column tab.
        -- ElvUI strips these on Blizzard's headers; this later-created header
        -- needs the same cleanup without touching its font, arrow or hover.
        for _,suffix in ipairs({"Left","Middle","Right"}) do
            local region=_G["Atr_BrowseMarketSort"..suffix]
            if region then region:SetTexture(nil) end
        end
        if not browseHeader.atrHover then
            local old=browseHeader:GetHighlightTexture()
            if old then old:SetTexture(nil) end
            local hover=browseHeader:CreateTexture()
            if hover.SetInside then hover:SetInside() else hover:SetAllPoints(browseHeader) end
            hover:SetTexture(1,1,1,.3)
            browseHeader.atrHover=hover
            browseHeader.hover=hover
        end
        browseHeader:SetHighlightTexture(browseHeader.atrHover)
        if not browseHeader.atrPushed then
            local pushed=browseHeader:CreateTexture()
            if pushed.SetInside then pushed:SetInside() else pushed:SetAllPoints(browseHeader) end
            pushed:SetTexture(.9,.8,.1,.3)
            browseHeader.atrPushed=pushed
            browseHeader.pushed=pushed
        end
        browseHeader:SetPushedTexture(browseHeader.atrPushed)
    end
    local arrow=browseHeader:GetNormalTexture()
    local nativeArrow=_G.BrowseQualitySortArrow or native:GetNormalTexture()
    if arrow then
        local width,height=8,8
        if nativeArrow and nativeArrow:GetWidth()>0 and nativeArrow:GetHeight()>0 then width,height=nativeArrow:GetWidth(),nativeArrow:GetHeight() end
        arrow:ClearAllPoints();arrow:SetSize(width,height)
        arrow:SetTexCoord(0,0.5625,browseDirection=="high" and 1 or 0,browseDirection=="high" and 0 or 1)
        if browseDirection then arrow:Show() else arrow:Hide() end
        local label=browseHeader:GetFontString()
        if label then
            label:ClearAllPoints();label:SetPoint("LEFT",browseHeader,"LEFT",2,0);label:SetWidth(math.min(74-width-6,label:GetStringWidth()));label:SetJustifyH("LEFT")
            arrow:SetPoint("LEFT",label,"RIGHT",3,-2)
            local nativeLabel=native:GetFontString()
            if nativeLabel then label:SetTextColor(nativeLabel:GetTextColor()) end
        else arrow:SetPoint("RIGHT",browseHeader,"RIGHT",-2,-2) end
    end
end
function Atr_UpdateBrowseMarketControls()
    installBrowseSort()
    fitBrowseRarityHeader(Atr_BrowseMarketColumnEnabled())
    if not browseHeader and BrowseLevelSort then
        browseHeader=CreateFrame("Button","Atr_BrowseMarketSort",AuctionFrameBrowse,"AuctionSortButtonTemplate")
        browseHeader:SetSize(74,19);browseHeader:SetPoint("RIGHT",BrowseLevelSort,"LEFT",-2,0)
        browseHeader:SetFrameLevel(BrowseLevelSort:GetFrameLevel()+3)
        browseHeader:SetNormalFontObject(GameFontNormalSmall);browseHeader:SetHighlightFontObject(GameFontHighlightSmall)
        browseHeader:SetHighlightTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight")
        browseHeader:SetNormalTexture("Interface\\Buttons\\UI-SortArrow")
        browseHeader:SetScript("OnClick",function()
            browseDirection=browseDirection=="low" and "high" or "low"
            FauxScrollFrame_SetOffset(BrowseScrollFrame,0);BrowseScrollFrame:SetVerticalScroll(0)
            if CloseAuctionStaticPopups then CloseAuctionStaticPopups() end
            AuctionFrameBrowse_Update()
        end)
        browseHeader:SetScript("OnEnter",function(self)
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:AddLine("Market %",1,0.82,0)
            GameTooltip:AddLine("Click to sort lowest / highest on this result page (up to 50 auctions).",1,1,1,true)
            GameTooltip:AddLine("Compares buyout per item with your saved reference. Missing prices sort last.",0.8,0.8,0.8,true)
            GameTooltip:Show()
        end)
        browseHeader:SetScript("OnLeave",function() GameTooltip:Hide() end)
    end
    if browseHeader then
        if Atr_BrowseMarketColumnEnabled() then
            browseHeader:Show();browseHeader:SetText("Market %");styleBrowseMarketHeader();fitBrowseRarityHeader(true)
            if fullScanActive() then browseHeader:Disable() else browseHeader:Enable() end
            if browseDirection then
                for _,name in ipairs({"BrowseQualitySort","BrowseLevelSort","BrowseDurationSort","BrowseHighBidderSort","BrowseCurrentBidSort"}) do
                    local button=_G[name];local arrow=_G[name.."Arrow"]
                    if arrow then arrow:Hide() end
                    local normal=button and button:GetNormalTexture()
                    if normal then normal:Hide() end
                end
            end
        else browseHeader:Hide() end
    end

end
browseCheck=CreateFrame("CheckButton","Atr_BrowseMarketColumnOption",Atr_BasicOptionsFrame,"UICheckButtonTemplate")
browseCheck:SetSize(24,24);browseCheck:SetPoint("TOPLEFT",Atr_BasicOptionsFrame,"TOPLEFT",30,-300)
local browseOptionText=browseCheck:CreateFontString(nil,"ARTWORK","GameFontHighlight")
browseOptionText:SetPoint("LEFT",browseCheck,"RIGHT",3,0);browseOptionText:SetText("Show Market % column on Browse")
browseCheck:SetScript("OnShow",function(self) self:SetChecked(Atr_BrowseMarketColumnEnabled()) end)
browseCheck:SetScript("OnClick",function(self) Atr_SetBrowseMarketColumnEnabled(self:GetChecked()) end)
