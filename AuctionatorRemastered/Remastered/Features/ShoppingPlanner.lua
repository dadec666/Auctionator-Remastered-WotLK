-- Offline editor for the original Auctionator shopping lists. No AH queries.
local function listIndex(list)
    for index,saved in ipairs(AUCTIONATOR_SHOPPING_LISTS or {}) do
        if saved == list and not saved.isRecents then return index end
    end
end
local function trim(text) return type(text)=="string" and text:match("^%s*(.-)%s*$") or "" end
local function changed(removed)
    if Atr_NotifyShoppingListsChanged then Atr_NotifyShoppingListsChanged(removed) end
end
function Atr_BrowserRenameShoppingList(list,name)
    if not listIndex(list) then return false,"Choose a saved shopping list." end
    name=trim(name)
    if name=="" then return false,"Enter a shopping list name." end
    if #name>32 then return false,"Shopping list names may have up to 32 characters." end
    local existing=Atr_SList.FindByName(name,{skipTempList=true})
    if existing and existing~=list then return false,"A shopping list with this name already exists." end
    local old=list.name
    list.name=name
    -- Shopping lists may contain references to other lists. Keep them valid.
    for _,other in ipairs(AUCTIONATOR_SHOPPING_LISTS) do
        for index,item in ipairs(other.items) do
            if string.lower(item)==string.lower("{ "..old.." }") then
                other.items[index]="{ "..name.." }";other.isSorted=false
            end
        end
    end
    changed()
    return true,"Shopping list renamed."
end
function Atr_BrowserEditShoppingItem(list,oldName,newName)
    if not listIndex(list) then return false,"Choose a saved shopping list." end
    if type(oldName)~="string" then return false,"Select an entry first." end
    local index=Atr_SList.FindItemIndex(list,oldName)
    if index==0 then return false,"This entry is no longer on the list." end
    newName=trim(newName)
    if newName=="" then return false,"Enter an item name or search term." end
    local duplicate=Atr_SList.FindItemIndex(list,newName)
    if duplicate>0 and duplicate~=index then return false,"Item is already on this shopping list." end
    if list.remasteredTargets and list.remasteredTargets[oldName] ~= nil then
        list.remasteredTargets[newName]=list.remasteredTargets[oldName];list.remasteredTargets[oldName]=nil
    end
    list.items[index]=newName;list.isSorted=false;changed()
    return true,"Entry updated."
end
function Atr_BrowserRemoveShoppingItem(list,name)
    if not listIndex(list) then return false,"Choose a saved shopping list." end
    if type(name)~="string" then return false,"Select an entry first." end
    local index=Atr_SList.FindItemIndex(list,name)
    if index==0 then return false,"This entry is no longer on the list." end
    table.remove(list.items,index)
    if list.remasteredTargets then list.remasteredTargets[name]=nil end
    list.isSorted=false;changed()
    return true,"Entry removed."
end
function Atr_BrowserDeleteShoppingList(list)
    local index=listIndex(list)
    if not index then return false,"This shopping list is no longer available." end
    table.remove(AUCTIONATOR_SHOPPING_LISTS,index)
    -- Remove references to the deleted list instead of leaving broken searches.
    for _,other in ipairs(AUCTIONATOR_SHOPPING_LISTS) do
        for i=#other.items,1,-1 do
            if string.lower(other.items[i])==string.lower("{ "..list.name.." }") then
                table.remove(other.items,i);other.isSorted=false
            end
        end
    end
    changed(list)
    return true,"Shopping list deleted."
end

function Atr_SetShoppingTarget(list,name,quantity)
    if not listIndex(list) or type(name)~="string" then return false,"Choose a shopping-list item." end
    local index=Atr_SList.FindItemIndex(list,name)
    if index==0 then return false,"This entry is no longer on the list." end
    quantity=tonumber(quantity)
    if not quantity or quantity~=math.floor(quantity) or quantity<0 or quantity>99999 then
        return false,"Enter a whole number from 0 to 99999."
    end
    if type(list.remasteredTargets)~="table" then list.remasteredTargets={} end
    list.remasteredTargets[list.items[index]]=quantity
    return true
end
function Atr_GetShoppingTarget(list,name)
    local value=type(list.remasteredTargets)=="table" and tonumber(list.remasteredTargets[name])
    if value and value==math.floor(value) and value>=0 and value<=99999 then return value end
    return 0
end

-- Pure planning arithmetic. Unknown search terms are excluded, not treated as
-- free items or zero inventory. Prices are always per individual item.
function Atr_BuildShoppingPlan(list,catalog,bags,bank,includeBank)
    local plan={rows={},total=0,need=0,ready=0,unpriced=0,unknown=0}
    if not list then return plan end
    for _,name in ipairs(list.items) do
        local info=catalog[name] or {}
        local row={name=name,info=info,want=Atr_GetShoppingTarget(list,name)}
        if info.known then
            row.bags=bags[name] or 0
            row.bank=bank and (bank[name] or 0) or nil
            row.owned=row.bags+(includeBank and row.bank or 0)
            row.need=math.max(0,row.want-row.owned)
            plan.need=plan.need+row.need
            if row.need==0 then row.cost=0;plan.ready=plan.ready+1
            elseif type(info.price)=="number" and info.price>0 then
                row.cost=row.need*info.price;plan.total=plan.total+row.cost
            else plan.unpriced=plan.unpriced+1 end
        else plan.unknown=plan.unknown+1 end
        plan.rows[#plan.rows+1]=row
    end
    table.sort(plan.rows,function(a,b) return string.lower(a.name)<string.lower(b.name) end)
    return plan
end

local function options()
    if type(AUCTIONATOR_BROWSER_SETTINGS)~="table" then AUCTIONATOR_BROWSER_SETTINGS={} end
    return AUCTIONATOR_BROWSER_SETTINGS
end
local function bankKey() return GetRealmName().."/"..UnitName("player") end
local function savedBank()
    local all=options().shoppingBanks
    return type(all)=="table" and all[bankKey()] or nil
end
local bankOpen=false
local function collectContainer(counts,bag)
    for slot=1,(GetContainerNumSlots(bag) or 0) do
        local link=GetContainerItemLink(bag,slot)
        if link then
            local name=GetItemInfo(link) or link:match("|h%[(.-)%]|h")
            local _,count=GetContainerItemInfo(bag,slot)
            if name and type(count)=="number" and count>0 then counts[name]=(counts[name] or 0)+count end
        end
    end
end
function Atr_GetShoppingBagCounts()
    local counts={}
    for bag=0,(NUM_BAG_SLOTS or 4) do collectContainer(counts,bag) end
    return counts
end
local function captureBank()
    if not bankOpen then return end
    if (GetContainerNumSlots(-1) or 0)==0 then return end
    local counts={}
    collectContainer(counts,-1)
    for bag=(NUM_BAG_SLOTS or 4)+1,(NUM_BAG_SLOTS or 4)+(NUM_BANKBAGSLOTS or 7) do collectContainer(counts,bag) end
    local config=options()
    if type(config.shoppingBanks)~="table" then config.shoppingBanks={} end
    config.shoppingBanks[bankKey()]={counts=counts,seen=time()}
end

local frame,listScroll,itemScroll,status,heading,empty,renameButton,deleteButton,removeButton
local totalText,progressText,coverageText,bankChoice,bankLabel
local listRows,itemRows,lists,catalog={},{},{},{}
local selectedList,selectedItem,focusedQuantity
local plan,bags={rows={}},nil
local LIST_ROWS,ROWS,HEIGHT=16,12,24
local refresh,renderItems
local function money(value)
    return value~=nil and gAtrZC.priceToMoneyString(math.floor(value+0.5)) or "--"
end
local function note(ok,message)
    status:SetText(message or "")
    status:SetTextColor(ok and 0.4 or 1,ok and 1 or 0.4,0.4)
end
local function resetScroll(scroll)
    FauxScrollFrame_SetOffset(scroll,0);scroll:SetVerticalScroll(0)
end
local function setEnabled(button,enabled)
    if enabled then button:Enable() else button:Disable() end
end
local function commitQuantity()
    if focusedQuantity then focusedQuantity:ClearFocus() end
end
local function resolveItem(name)
    local info=catalog[name]
    if info then return info end
    local cached=(AUCTIONATOR_BROWSER_ITEMS or {})[name] or {}
    local base=Atr_GetBaseItemInfo and Atr_GetBaseItemInfo(name) or {}
    local known,link,quality,_,_,_,_,_,_,texture=GetItemInfo(name)
    info={known=(known and string.lower(known)==string.lower(name)) or cached.link~=nil or (base and base.itemString~=nil),
        texture=texture or cached.texture or (base and base.texture),link=link or cached.link}
    catalog[name]=info
    return info
end
local function rebuildPrices()
    catalog={}
    for _,entry in ipairs(Atr_BuildBrowserSnapshot()) do entry.known=true;catalog[entry.name]=entry end
end
local function renderLists()
    local offset=math.min(FauxScrollFrame_GetOffset(listScroll),math.max(0,#lists-LIST_ROWS))
    FauxScrollFrame_SetOffset(listScroll,offset);FauxScrollFrame_Update(listScroll,#lists,LIST_ROWS,22)
    for i,row in ipairs(listRows) do
        row.list=lists[offset+i]
        if row.list then
            row.label:SetText(row.list.name.." ("..#row.list.items..")")
            if row.list==selectedList then row:LockHighlight() else row:UnlockHighlight() end
            row:Show()
        else row:Hide() end
    end
end
renderItems=function()
    bags=Atr_GetShoppingBagCounts()
    local bank=savedBank()
    local include=options().shoppingIncludeBank~=false
    if selectedList then
        for _,name in ipairs(selectedList.items) do
            local info=resolveItem(name)
            -- Inventory names also establish an exact identity when offline metadata is absent.
            if bags[name]~=nil or (bank and bank.counts[name]~=nil) then info.known=true end
        end
    end
    plan=Atr_BuildShoppingPlan(selectedList,catalog,bags,bank and bank.counts,include)
    local database=type(gAtr_ScanDB)=="table" and gAtr_ScanDB or
        (AUCTIONATOR_PRICE_DATABASE or {})[GetRealmName().."_"..UnitFactionGroup("player")]
    local offset=math.min(FauxScrollFrame_GetOffset(itemScroll),math.max(0,#plan.rows-ROWS))
    FauxScrollFrame_SetOffset(itemScroll,offset);FauxScrollFrame_Update(itemScroll,#plan.rows,ROWS,HEIGHT)
    for i,row in ipairs(itemRows) do
        local data=plan.rows[offset+i];row.data=data;row.itemName=data and data.name
        if data then
            row.label:SetText(data.name)
            row.icon:SetTexture(data.info.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
            if not row.want:HasFocus() then row.want:SetText(tostring(data.want)) end
            -- 3.3.5 EditBoxes do not consistently provide Button's Enable/Disable.
            row.want.planEnabled=data.info.known==true
            row.want:EnableMouse(row.want.planEnabled)
            row.want:SetTextColor(row.want.planEnabled and 1 or 0.5,row.want.planEnabled and 1 or 0.5,row.want.planEnabled and 1 or 0.5)
            row.owned:SetText(data.owned~=nil and tostring(data.owned) or "--")
            row.need:SetText(data.need~=nil and tostring(data.need) or "--")
            row.need:SetTextColor(data.need==0 and 0.4 or 1,data.need==0 and 1 or 0.82,0.3)
            row.label:SetTextColor(data.need==0 and 0.65 or 1,data.need==0 and 0.9 or 1,data.need==0 and 0.65 or 1)
            row.price:SetText(money(data.info.price));row.cost:SetText(money(data.cost))
            row.percent:SetText(data.info.price and Atr_MarketPercentText(data.name,data.info.price,1,database) or "--")
            if selectedItem==data.name then row:LockHighlight() else row:UnlockHighlight() end
            row:Show()
        else row:Hide() end
    end
    heading:SetText(selectedList and (selectedList.name.."  ("..#plan.rows.." / "..ATR_MAXNUM_ITEMS_ON_SHOPPING_LIST..")") or "Choose or create a shopping list")
    progressText:SetText("Need: |cffffd100"..plan.need.."|r items    Ready: |cff66ff66"..plan.ready.."|r / "..(#plan.rows-plan.unknown))
    local totalLabel=(plan.unpriced>0 or plan.unknown>0) and "Partial estimate: " or
        (include and not bank and "Bags-only estimate: " or "Estimated total: ")
    totalText:SetText(totalLabel..money(plan.total))
    local details={}
    if plan.unpriced>0 then details[#details+1]=plan.unpriced.." entries without prices" end
    if plan.unknown>0 then details[#details+1]=plan.unknown.." search terms excluded" end
    if include and not bank then details[#details+1]="Visit your bank to include stored items"
    elseif include then details[#details+1]="Bags + last recorded bank"
    else details[#details+1]="Bags only" end
    coverageText:SetText(table.concat(details,"  |  "))
    bankChoice:SetChecked(include)
    bankLabel:SetText(include and not bank and "Include bank (not recorded)" or "Include bank")
    empty:SetText(not selectedList and "Create a list to start planning your purchases." or (#plan.rows==0 and "This shopping list is empty." or ""))
    setEnabled(renameButton,selectedList~=nil);setEnabled(deleteButton,selectedList~=nil)
    setEnabled(removeButton,selectedItem~=nil)
end
refresh=function()
    lists={}
    for _,list in ipairs(AUCTIONATOR_SHOPPING_LISTS or {}) do if not list.isRecents then lists[#lists+1]=list end end
    table.sort(lists,function(a,b) return string.lower(a.name)<string.lower(b.name) end)
    if not listIndex(selectedList) then selectedList=lists[1];selectedItem=nil end
    if selectedItem and (not selectedList or Atr_SList.FindItemIndex(selectedList,selectedItem)==0) then selectedItem=nil end
    renderLists();renderItems()
end
local function finishPopup(popup)
    local data=popup.data;if not data then return true end
    local ok,message,list
    if data.mode=="new" then
        ok,message,list=Atr_BrowserCreateShoppingList(popup.editBox:GetText())
        if ok then selectedList=list;selectedItem=nil;resetScroll(itemScroll) end
    else ok,message=Atr_BrowserRenameShoppingList(data.list,popup.editBox:GetText()) end
    note(ok,message);if ok then refresh() end
    return not ok
end
-- Share the browser theme while preserving an independent opacity preference.
local function stylePlannerSurface(surface,body)
    Atr_StyleOfflineBrowser(surface,body,options().shoppingTransparent==true)
end
local function create()
    frame=CreateFrame("Frame","Atr_BrowserShoppingLists",UIParent)
    frame:SetSize(1100,570);frame:SetPoint("CENTER");frame:SetFrameStrata("DIALOG");frame:SetFrameLevel(50)
    frame:SetClampedToScreen(true);frame:SetMovable(true);frame:EnableMouse(true);frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart",function(self) commitQuantity();self:StartMoving() end)
    frame:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
    stylePlannerSurface(frame,false)
    local function text(parent,value,x,y,width,template)
        local label=parent:CreateFontString(nil,"OVERLAY",template or "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y);label:SetWidth(width);label:SetJustifyH("LEFT");label:SetText(value)
        return label
    end
    local function button(label,x,y,width,callback,parent)
        parent=parent or frame
        local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
        Atr_AnalysisSkin(b,"Button")
        b:SetPoint("TOPLEFT",parent,"TOPLEFT",x,y);b:SetSize(width,22);b:SetText(label)
        b:SetScript("OnClick",function() commitQuantity();callback() end)
        return b
    end
    local title=text(frame,"Shopping planner",0,-12,600,"GameFontNormal")
    title:ClearAllPoints();title:SetPoint("TOP",frame,"TOP",0,-12);title:SetJustifyH("CENTER")
    text(frame,"Planning for "..UnitName("player")..". Lists are shared with Buy.",24,-49,800)
    local close=CreateFrame("Button",nil,frame,"UIPanelCloseButton")
    Atr_AnalysisSkin(close,"CloseButton")
    close:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-5,-5);close:SetScript("OnClick",function() commitQuantity();frame:Hide() end)
    local listPanel=CreateFrame("Frame","Atr_ShoppingListsBackground",frame)
    listPanel:SetPoint("TOPLEFT",frame,"TOPLEFT",14,-70);listPanel:SetSize(212,473)
    stylePlannerSurface(listPanel,true)
    local results=CreateFrame("Frame","Atr_ShoppingResultsBackground",frame)
    results:SetPoint("TOPLEFT",frame,"TOPLEFT",241,-178);results:SetSize(831,296)
    results:SetFrameLevel(frame:GetFrameLevel());stylePlannerSurface(results,true)
    local function updateBackgrounds()
        stylePlannerSurface(frame,false);stylePlannerSurface(listPanel,true);stylePlannerSurface(results,true)
    end
    local backgroundChoice=Atr_CreateBackgroundCheckbox(frame,"Atr_ShoppingTransparentBackground",options().shoppingTransparent==true,function(checked)
        commitQuantity();options().shoppingTransparent=checked;updateBackgrounds()
    end)
    -- The list selector includes its management buttons; its scroll gutter stays inside that group.
    local listBounds=CreateFrame("Frame","Atr_ShoppingListBounds",listPanel)
    listBounds:SetPoint("TOPLEFT",listPanel,"TOPLEFT",6,-46);listBounds:SetSize(174,LIST_ROWS*22)
    text(listPanel,"Your lists",10,-7,190,"GameFontNormal")
    heading=text(frame,"",245,-77,600,"GameFontNormal")
    progressText=text(frame,"",245,-107,320,"GameFontHighlight")
    totalText=text(frame,"",590,-107,480,"GameFontNormal")
    coverageText=text(frame,"",245,-132,825,"GameFontDisableSmall")
    bankChoice=CreateFrame("CheckButton","Atr_ShoppingIncludeBank",frame,"UICheckButtonTemplate")
    Atr_AnalysisSkin(bankChoice,"CheckBox")
    bankChoice:SetPoint("TOPLEFT",frame,"TOPLEFT",855,-72);bankChoice:SetSize(24,24)
    bankLabel=text(frame,"Include bank",882,-77,200)
    bankChoice:SetScript("OnClick",function(self)
        local checked=self:GetChecked()
        commitQuantity();options().shoppingIncludeBank=checked and true or false;renderItems()
    end)
    bankChoice:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:AddLine("Owned items",1,0.82,0)
        GameTooltip:AddLine("Counts this character's bags and the last recorded bank contents. Equipped items, alts and guild banks are excluded.",1,1,1,true)
        local bank=savedBank()
        GameTooltip:AddLine(bank and ("Bank recorded: "..date("%Y-%m-%d %H:%M",bank.seen)) or "Bank not recorded yet. Open your bank once to include it.",0.8,0.8,0.8,true)
        GameTooltip:Show()
    end)
    bankChoice:SetScript("OnLeave",function() GameTooltip:Hide() end)
    for _,spec in ipairs({{"Item",277,220},{"Want",511,50},{"Owned",566,50},{"Need",626,50},{"Last scan / item",690,145},{"Est. cost",845,140},{"Market %",990,80}}) do
        text(frame,spec[1],spec[2],-158,spec[3],"GameFontNormalSmall")
    end
    listScroll=CreateFrame("ScrollFrame","Atr_BrowserShoppingListScroll",listPanel,"FauxScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT",listPanel,"TOPLEFT",6,-46);listScroll:SetSize(174,LIST_ROWS*22)
    listScroll:SetScript("OnVerticalScroll",function(self,offset) commitQuantity();FauxScrollFrame_OnVerticalScroll(self,offset,22,renderLists) end)
    itemScroll=CreateFrame("ScrollFrame","Atr_BrowserShoppingItemScroll",frame,"FauxScrollFrameTemplate")
    itemScroll:SetPoint("TOPLEFT",frame,"TOPLEFT",245,-182);itemScroll:SetSize(823,ROWS*HEIGHT)
    itemScroll:SetScript("OnVerticalScroll",function(self,offset) commitQuantity();FauxScrollFrame_OnVerticalScroll(self,offset,HEIGHT,renderItems) end)
    Atr_StyleAnalysisScroll(listScroll,listBounds)
    Atr_StyleAnalysisScroll(itemScroll,results)
    empty=text(frame,"",300,-300,700)
    for i=1,LIST_ROWS do
        local row=CreateFrame("Button",nil,listPanel);listRows[i]=row
        row:SetPoint("TOPLEFT",listPanel,"TOPLEFT",6,-46-(i-1)*22);row:SetSize(174,22)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight");row.label=text(row,"",4,-4,166)
        row:SetScript("OnClick",function(self)
            commitQuantity();selectedList=self.list;selectedItem=nil;status:SetText("");resetScroll(itemScroll);refresh()
        end)
    end
    for i=1,ROWS do
        local item=CreateFrame("Button",nil,frame);itemRows[i]=item
        item:SetPoint("TOPLEFT",frame,"TOPLEFT",245,-182-(i-1)*HEIGHT);item:SetSize(823,HEIGHT)
        if i%2==0 then
            local shade=item:CreateTexture(nil,"BACKGROUND");shade:SetTexture(1,1,1,0.035);shade:SetAllPoints(item)
        end
        item:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        item.icon=item:CreateTexture(nil,"ARTWORK");item.icon:SetSize(20,20);item.icon:SetPoint("LEFT",item,"LEFT",5,0)
        item.label=text(item,"",32,-6,225);item.owned=text(item,"",321,-6,50);item.need=text(item,"",381,-6,50)
        item.price=text(item,"",445,-6,145);item.cost=text(item,"",600,-6,140);item.percent=text(item,"",745,-6,70)
        item.want=CreateFrame("EditBox","Atr_ShoppingWant"..i,item,"InputBoxTemplate")
        Atr_AnalysisSkin(item.want,"EditBox")
        item.want:SetPoint("LEFT",item,"LEFT",268,0);item.want:SetSize(42,20)
        -- InputBoxTemplate's middle texture is translucent; cover the row shade
        -- beneath it while leaving the template's border and text on top.
        local quantityBackground=item.want:CreateTexture(nil,"BACKGROUND")
        quantityBackground:SetTexture("Interface\\Buttons\\WHITE8X8")
        quantityBackground:SetVertexColor(0.025,0.025,0.03,1)
        quantityBackground:SetPoint("TOPLEFT",item.want,"TOPLEFT",-3,0)
        quantityBackground:SetPoint("BOTTOMRIGHT",item.want,"BOTTOMRIGHT",0,0)
        item.want:SetAutoFocus(false);item.want:SetNumeric(true);item.want:SetMaxLetters(5)
        item.want:SetScript("OnEditFocusGained",function(self)
            focusedQuantity=self;selectedItem=item.itemName
            self.editingName=item.itemName;self.editingList=selectedList
        end)
        item.want:SetScript("OnEditFocusLost",function(self)
            focusedQuantity=nil
            local name,list=self.editingName,self.editingList
            self.editingName=nil;self.editingList=nil
            if not name then return end
            local ok,message=Atr_SetShoppingTarget(list,name,self:GetText())
            if not ok then note(false,message) end
            renderItems()
        end)
        item.want:SetScript("OnEnterPressed",function(self) self:ClearFocus() end)
        item.want:SetScript("OnEscapePressed",function(self)
            if item.itemName then self:SetText(tostring(Atr_GetShoppingTarget(selectedList,item.itemName))) end
            self:ClearFocus()
        end)
        item:SetScript("OnClick",function(self) commitQuantity();selectedItem=self.itemName;status:SetText("");renderItems() end)
        item:SetScript("OnEnter",function(self)
            local data=self.data;if not data then return end
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:AddLine(data.name,1,0.82,0)
            if data.info.known then
                GameTooltip:AddLine("Bags: "..data.bags.." | Bank: "..(data.bank~=nil and data.bank or "not recorded"),1,1,1)
                GameTooltip:AddLine("Want is your total target. Need = target minus owned; never below zero.",1,1,1,true)
                GameTooltip:AddLine("Estimated cost uses Need times the last saved lowest price per item. Actual AH prices may differ.",0.8,0.8,0.8,true)
                if data.info.historyDays and data.info.historyDays<3 then GameTooltip:AddLine("* Preliminary: fewer than 3 history days.",1,0.82,0) end
            else GameTooltip:AddLine("No exact item match. This search term is excluded from quantity and cost totals.",0.8,0.8,0.8,true) end
            GameTooltip:Show()
        end)
        item:SetScript("OnLeave",function() GameTooltip:Hide() end)
    end
    removeButton=button("Remove entry",245,-521,130,function()
        local ok,message=Atr_BrowserRemoveShoppingItem(selectedList,selectedItem)
        if ok then selectedItem=nil end
        note(ok,message);refresh()
    end)
    status=text(frame,"",395,-525,540)
    button("Close",970,-535,102,function() frame:Hide() end)
    text(frame,"Set Want to the total quantity you want to own. Press Enter or click away to save.",245,-490,825,"GameFontDisableSmall")
    StaticPopupDialogs["ATR_BROWSER_LIST_NAME"]={
        text="Shopping list name",button1=ACCEPT,button2=CANCEL,hasEditBox=1,maxLetters=32,
        timeout=0,exclusive=1,whileDead=1,hideOnEscape=1,
        OnShow=function(self)
            self:SetFrameStrata("FULLSCREEN_DIALOG");self.editBox:SetText(self.data and self.data.list and self.data.list.name or "")
            self.editBox:SetFocus();self.editBox:HighlightText()
        end,
        OnAccept=finishPopup,
        EditBoxOnEnterPressed=function(self) if not finishPopup(self:GetParent()) then self:GetParent():Hide() end end,
        EditBoxOnEscapePressed=function(self) self:GetParent():Hide() end,
    }
    StaticPopupDialogs["ATR_BROWSER_LIST_DELETE"]={
        text="Delete shopping list %s?\n\nReferences to this list in other shopping lists will also be removed.",
        button1=YES,button2=NO,timeout=0,exclusive=1,whileDead=1,hideOnEscape=1,
        OnShow=function(self) self:SetFrameStrata("FULLSCREEN_DIALOG") end,
        OnAccept=function(self)
            local ok,message=Atr_BrowserDeleteShoppingList(self.data)
            note(ok,message);selectedItem=nil;refresh()
        end,
    }
    button("New",6,-439,54,function() StaticPopup_Show("ATR_BROWSER_LIST_NAME",nil,nil,{mode="new"}) end,listPanel)
    renameButton=button("Rename",66,-439,70,function()
        if selectedList then StaticPopup_Show("ATR_BROWSER_LIST_NAME",nil,nil,{mode="rename",list=selectedList}) end
    end,listPanel)
    deleteButton=button("Delete",142,-439,60,function()
        if selectedList then StaticPopup_Show("ATR_BROWSER_LIST_DELETE",selectedList.name,nil,selectedList) end
    end,listPanel)
    frame:SetScript("OnShow",function(self)
        backgroundChoice:SetChecked(options().shoppingTransparent==true)
        updateBackgrounds()
        Atr_StyleAnalysisScroll(listScroll,listBounds);Atr_StyleAnalysisScroll(itemScroll,results)
        self:SetScale(math.max(0.5,math.min(1,(UIParent:GetWidth()-30)/1100,(UIParent:GetHeight()-40)/570)))
        if bankOpen then captureBank() end
        rebuildPrices();refresh()
    end)
    frame:SetScript("OnHide",function()
        commitQuantity();StaticPopup_Hide("ATR_BROWSER_LIST_NAME");StaticPopup_Hide("ATR_BROWSER_LIST_DELETE")
    end)
    local wasDown=false
    frame:SetScript("OnUpdate",function()
        local down=IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
        if down and not wasDown and focusedQuantity and not MouseIsOver(focusedQuantity) then commitQuantity() end
        wasDown=down
    end)
    table.insert(UISpecialFrames,"Atr_BrowserShoppingLists");frame:Hide()
end
function Atr_ShowBrowserShoppingLists(list)
    if not frame then create() end
    commitQuantity()
    if listIndex(list) then selectedList=list;selectedItem=nil;resetScroll(itemScroll) end
    if frame:IsShown() then rebuildPrices();refresh() end
    CloseDropDownMenus();frame:Show()
end
local events=CreateFrame("Frame")
for _,event in ipairs({"BAG_UPDATE","BANKFRAME_OPENED","BANKFRAME_CLOSED","PLAYERBANKSLOTS_CHANGED","PLAYER_ENTERING_WORLD","AUCTION_HOUSE_CLOSED"}) do events:RegisterEvent(event) end
local pending
local function updateInventory()
    if bankOpen then captureBank() end
    if frame and frame:IsShown() then renderItems() end
end
events:SetScript("OnEvent",function(self,event)
    if event=="AUCTION_HOUSE_CLOSED" then
        if frame and frame:IsShown() then frame:Hide() end
    elseif event=="BANKFRAME_OPENED" then bankOpen=true;updateInventory()
    elseif event=="BANKFRAME_CLOSED" then bankOpen=false;updateInventory()
    elseif event=="PLAYER_ENTERING_WORLD" then bankOpen=false;pending=0.2
    else
        -- Preserve changes before the player can immediately close the bank.
        if bankOpen then captureBank() end
        pending=0.2
    end
end)
events:SetScript("OnUpdate",function(self,elapsed)
    if pending then pending=pending-elapsed;if pending<=0 then pending=nil;updateInventory() end end
end)
AuctionatorRemastered.Legacy.Hook("Atr_Broadcast_DBupdated",function()
    if frame and frame:IsShown() then rebuildPrices();refresh() end
end)
