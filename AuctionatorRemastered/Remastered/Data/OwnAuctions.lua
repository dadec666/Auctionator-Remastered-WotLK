-- A separate posting ledger. Does not infer completed sales from listings.
local function ledger()
    if type(AUCTIONATOR_OWN_AUCTIONS) ~= "table" then AUCTIONATOR_OWN_AUCTIONS = {} end
    local key = GetRealmName().."_"..UnitFactionGroup("player")
    if not AUCTIONATOR_OWN_AUCTIONS[key] then
        AUCTIONATOR_OWN_AUCTIONS[key] = {since = time(), records = {}}
    end
    return AUCTIONATOR_OWN_AUCTIONS[key]
end

AuctionatorRemastered.Legacy.Hook("Atr_LogMsg", function(link, stackSize, stackPrice, stacks)
    local name = GetItemInfo(link) or (type(link) == "string" and link:match("|h%[(.-)%]|h"))
    if not name or not stackSize or stackSize <= 0 or not stackPrice or not stacks or stacks <= 0 then return end
    local log = ledger()
    local identity=AuctionatorRemastered.Models.ItemIdentity
    log.records[#log.records + 1] = {
        name = name, link = link, itemKey=identity and identity.Parse(link), when = time(), stackSize = stackSize,
        stacks = stacks, stackPrice = stackPrice, character = UnitName("player"),
    }
    -- Bound account data independently of the market-price database.
    while #log.records > 5000 or (#log.records > 0 and log.records[1].when < time() - 180 * 86400) do
        table.remove(log.records, 1)
    end
end)

function Atr_BuildOwnAuctionRows(itemName)
    local log, rows = ledger(), {}
    for _, record in ipairs(log.records) do
        if record.name == itemName then
            rows[#rows + 1] = {
                when = record.when, itemPrice = record.stackPrice / record.stackSize,
                stackSize = record.stackSize, stacks = record.stacks,
                quantity = record.stackSize * record.stacks,
                total = record.stackPrice * record.stacks,
                character = record.character, yours = true, type = "hx", ownLedger = true,
                status = "Posted", whenText = date("%Y-%m-%d %H:%M", record.when),
            }
        end
    end
    local history = AUCTIONATOR_PRICING_HISTORY and AUCTIONATOR_PRICING_HISTORY[itemName]
    if type(history) == "table" then
        for tag, value in pairs(history) do
            if tag ~= "is" then
                local when, kind, price, size, count = ParseHist(tag, value)
                -- The legacy logger rounds to minutes and can overwrite batches.
                -- Only import entries predating this ledger's first minute.
                if when and price and when < math.floor(log.since / 60) * 60 then
                    rows[#rows + 1] = {
                        when = when, itemPrice = price, stackSize = size,
                        quantity = kind == "hx" and size or nil,
                        yours = true, type = kind, status = "Legacy",
                        whenText = kind == "hx" and date("%Y-%m-%d %H:%M", when) or date("%Y-%m-%d", when).." avg",
                    }
                end
            end
        end
    end
    table.sort(rows, function(a,b) return a.when > b.when end)
    return rows
end

local ownHeadings = {}
local function hideExtras()
    for _, heading in ipairs(ownHeadings) do heading:Hide() end
    for i = 1, 12 do
        local row = _G["AuctionatorEntry"..i]
        if row and row.atrOwnLabels then
            for _, text in ipairs(row.atrOwnLabels) do text:Hide() end
        end
    end
end
AuctionatorRemastered.Legacy.Hook("Atr_ShowCurrentAuctions", hideExtras)
AuctionatorRemastered.Legacy.Hook("Atr_ShowSearchSummary", hideExtras)
AuctionatorRemastered.Legacy.Hook("Atr_ShowHistory", hideExtras)

local function labels(row)
    if not row.atrOwnLabels then
        row.atrOwnLabels = {}
        for i, spec in ipairs({{155,108}, {270,132}, {510,72}, {410,92}}) do
            local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetPoint("LEFT", row, "LEFT", spec[1], 0)
            text:SetWidth(spec[2]); text:SetJustifyH("LEFT")
            row.atrOwnLabels[i] = text
        end
        row:HookScript("OnEnter", function(self)
            if not Atr_IsSelectedTab_Hints() and PanelTemplates_GetSelectedTab(Atr_ListTabs) ~= 4 then return end
            local pane = Atr_GetCurrentPane()
            local data = pane and pane.sortedHist and pane.sortedHist[self:GetID()]
            if not data then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(data.purchase and "Auctionator purchase record" or (data.ownLedger and "Auctionator posting record" or "Legacy posting record"), 1, 0.82, 0)
            GameTooltip:AddLine("Date: "..data.whenText, 1, 1, 1)
            if data.quantity then GameTooltip:AddLine("Items: "..data.quantity, 1, 1, 1) end
            if data.stacks then GameTooltip:AddLine("Stacks: "..data.stacks.." x "..data.stackSize, 1, 1, 1) end
            if data.total then GameTooltip:AddLine((data.purchase and "Total paid: " or "Total listed value: ")..gAtrZC.priceToMoneyString(math.floor(data.total)), 1, 1, 1) end
            if data.seller then GameTooltip:AddLine("Seller: "..data.seller, 1, 1, 1) end
            if data.character then GameTooltip:AddLine("Character: "..data.character, 1, 1, 1) end
            GameTooltip:Show()
        end)
        row:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return row.atrOwnLabels
end

-- Retain the native history renderer and row selection/recommendation behavior.
function Atr_ShowOldPostings()
    local pane = Atr_GetCurrentPane()
    if not pane or pane:IsScanNil() then hideExtras(); return end
    local purchases = PanelTemplates_GetSelectedTab(Atr_ListTabs) == 4
    pane.sortedHist = purchases and Atr_BuildPurchaseRows(pane.activeScan.itemName) or Atr_BuildOwnAuctionRows(pane.activeScan.itemName)
    Atr_ShowHistory(true)
    Atr_Col1_Heading:SetText("Price / item")
    Atr_Col3_Heading:Hide()
    Atr_Col4_Heading:Hide()
    if #ownHeadings == 0 then
        for _, spec in ipairs({{"Items / stacks", -50, 108}, {"Date / time", 65, 132}, {"Character", 205, 92}, {"Status", 305, 72}}) do
            local heading = Atr_HeadingsBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            heading:SetPoint("LEFT", Atr_Col3_Heading, "LEFT", spec[2], 0)
            heading:SetWidth(spec[3]); heading:SetJustifyH("LEFT")
            heading:SetText(spec[1])
            ownHeadings[#ownHeadings + 1] = heading
        end
    end
    ownHeadings[4]:SetText(purchases and "Seller" or "Status")
    if #pane.sortedHist == 0 then
        for _, heading in ipairs(ownHeadings) do heading:Hide() end
        Atr_SetMessage(purchases and "No purchases recorded for this item yet." or "No own auction records for this item yet.")
    else
        for _, heading in ipairs(ownHeadings) do heading:Show() end
        Atr_SetMessage("")
    end
    for i = 1, 12 do
        local row = _G["AuctionatorEntry"..i]
        local data = pane.sortedHist[row:GetID()]
        if data and row:IsShown() then
            _G["AuctionatorEntry"..i.."_EntryText"]:SetText("")
            local text = labels(row)
            text[1]:SetText(data.stacks and (data.quantity.." ("..data.stacks.." x "..data.stackSize..")") or (data.quantity and tostring(data.quantity).."*" or "Unknown*"))
            text[2]:SetText(data.whenText)
            text[4]:SetText(data.character or "--")
            text[3]:SetText(purchases and (data.seller or "--") or data.status)
            if purchases then
                text[3]:SetTextColor(1, 1, 1)
            else
                text[3]:SetTextColor(data.ownLedger and 0.6 or 0.7, data.ownLedger and 0.9 or 0.7, data.ownLedger and 1 or 0.7)
            end
            for _, field in ipairs(text) do field:Show() end
        end
    end
end
AuctionatorRemastered.Legacy.Hook("Atr_Init", function()
    ledger()
    if Atr_ListTabsTab3 then Atr_ListTabsTab3:SetText("My Auctions") end
end)
