-- DragonUI 3.0 Integration for Auctionator Remastered.
-- Adapts action buttons, tabs, scrollbars, inputs and dialogs to DragonUI's Dragonflight design.

local function isDragonUILoaded()
    return type(_G.DragonUI) == "table" and type(_G.DragonUI.ForeverUI) == "table"
end

local skinnedButtons = setmetatable({}, { __mode = "k" })
local skinnedTabs = setmetatable({}, { __mode = "k" })
local skinnedInputs = setmetatable({}, { __mode = "k" })

local function skinDragonUIButtons()
    if not isDragonUILoaded() then
        return
    end
    local F = _G.DragonUI.ForeverUI
    if not F or not F.SkinButton then
        return
    end

    local buttonNames = {
        "Atr_FullScanButton",
        "Auctionator1Button",
        "AuctionatorCloseButton",
        "Atr_CancelSelectionButton",
        "Atr_Buy1_Button",
        "Atr_Search_Button",
        "Atr_Adv_Search_Button",
        "Atr_Back_Button",
        "Atr_AddToSListButton",
        "Atr_RemFromSListButton",
        "Atr_SrchSListButton",
        "Atr_MngSListsButton",
        "Atr_NewSListButton",
        "Atr_SaveThisList_Button",
        "Atr_CreateAuctionButton",
        "Atr_CheckActiveButton",
        "Atr_Buy_Confirm_OKBut",
        "Atr_Buy_Confirm_CancelBut",
        "Atr_FullScanStartButton",
        "Atr_FullScanDone",
        "Atr_ResetAuctionPosition",
        "Atr_ResetDetailsPosition",
    }

    for _, name in ipairs(buttonNames) do
        local button = _G[name]
        if button and not skinnedButtons[button] then
            F.SkinButton(button)
            skinnedButtons[button] = true
        end
    end
end

local function skinDragonUITabs()
    if not isDragonUILoaded() or not AuctionFrame then
        return
    end
    local CP = _G.DragonUI.CharacterPanel
    if not CP or not CP.ReskinTab then
        return
    end

    for i = 1, (AuctionFrame.numTabs or 0) do
        local tab = _G["AuctionFrameTab" .. i]
        if tab and not skinnedTabs[tab] then
            CP.ReskinTab(tab)
            skinnedTabs[tab] = true
        end
    end

    for i = 1, 4 do
        local tab = _G["Atr_ListTabsTab" .. i]
        if tab and not skinnedTabs[tab] then
            CP.ReskinTab(tab, true)
            skinnedTabs[tab] = true
        end
    end
end

local function skinDragonUIInputs()
    if not isDragonUILoaded() then
        return
    end
    local F = _G.DragonUI.ForeverUI

    -- Scrollbars
    if F.SkinScrollBar then
        local scrollbars = {
            "AuctionatorScrollFrame",
            "Atr_Hlist_ScrollFrame",
            "Atr_FullScanResults",
        }
        for _, name in ipairs(scrollbars) do
            local frame = _G[name]
            if frame and not skinnedInputs[frame] then
                F.SkinScrollBar(frame)
                skinnedInputs[frame] = true
            end
        end
    end

    -- EditBoxes
    if F.SkinEditBox then
        local boxes = {
            "Atr_Buy_Confirm_Numstacks",
            "Atr_StackPrice",
            "Atr_ItemPrice",
            "Atr_Batch_NumAuctions",
            "Atr_Batch_Stacksize",
            "Atr_StartingPrice",
            "Atr_Custom_Price",
        }
        for _, name in ipairs(boxes) do
            local box = _G[name]
            if box and not skinnedInputs[box] then
                F.SkinEditBox(box)
                skinnedInputs[box] = true
            end
        end
    end
end

-- Defer execution so Blizzard and addon scripts can finish layout setup
local pending = CreateFrame("Frame")
pending:Hide()
local function schedule()
    if not isDragonUILoaded() then
        return
    end
    pending:Show()
end

pending:SetScript("OnUpdate", function(self)
    self:Hide()
    skinDragonUIButtons()
    skinDragonUITabs()
    skinDragonUIInputs()
end)

if AuctionatorRemastered and AuctionatorRemastered.Legacy and AuctionatorRemastered.Legacy.Hook then
    AuctionatorRemastered.Legacy.Hook("Atr_AuctionFrameTab_OnClick", schedule)
    AuctionatorRemastered.Legacy.Hook("Atr_UpdateUI", schedule)
    AuctionatorRemastered.Legacy.Hook("Atr_ListTabOnClick", schedule)
    AuctionatorRemastered.Legacy.Hook("Atr_ShowCurrentAuctions", schedule)
    AuctionatorRemastered.Legacy.Hook("Atr_ShowHistory", schedule)
    AuctionatorRemastered.Legacy.Hook("Atr_ShowSearchSummary", schedule)
    AuctionatorRemastered.Legacy.Hook("Atr_ShowHide_StartingPrice", schedule)
    AuctionatorRemastered.Legacy.Hook("Atr_ShowFullScanFrame", schedule)
    AuctionatorRemastered.Legacy.Hook("Atr_Buy1_Onclick", schedule)
    AuctionatorRemastered.Legacy.Hook("Atr_Init", function()
        if Atr_Main_Panel then
            Atr_Main_Panel:HookScript("OnShow", schedule)
        end
        if AuctionFrame then
            AuctionFrame:HookScript("OnShow", schedule)
        end
        schedule()
    end)
end
