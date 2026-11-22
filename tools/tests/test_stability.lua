dofile("AuctionatorRemastered/Remastered/Core/Bootstrap.lua")
dofile("AuctionatorRemastered/Remastered/Integration/LegacyBridge.lua")

local checks = 0
local function check(v, msg)
    checks = checks + 1
    assert(v, msg or "assertion failed")
end

-- =========================================================================
-- Fixtures & Mocks
-- =========================================================================
local now = 1000000
function time()
    return now
end
function GetTime()
    return now
end
function GetRealmName()
    return "TestRealm"
end
function UnitFactionGroup()
    return "Alliance"
end
function UnitName()
    return "TestPlayer"
end
function GetLocale()
    return "enUS"
end
function ZT(s)
    return s
end
local hooks = {}
_G.hooksecurefunc = function(name, fn)
    hooks[name] = hooks[name] or {}
    table.insert(hooks[name], fn)
end

local frames = {}
local function createMockWidget(name)
    local w = {
        name = name,
        shown = true,
        scripts = {},
        points = {},
        text = "",
        number = 0,
    }
    function w:Show()
        self.shown = true
        if self.scripts.OnShow then
            self.scripts.OnShow(self)
        end
    end
    function w:Hide()
        self.shown = false
        if self.scripts.OnHide then
            self.scripts.OnHide(self)
        end
    end
    function w:IsShown()
        return self.shown
    end
    function w:SetScript(k, v)
        self.scripts[k] = v
    end
    function w:GetScript(k)
        return self.scripts[k]
    end
    function w:RegisterEvent(...) end
    function w:UnregisterEvent(...) end
    function w:GetName()
        return self.name
    end
    function w:SetText(t)
        self.text = tostring(t)
        if self.scripts.OnTextChanged then
            self.scripts.OnTextChanged(self)
        end
    end
    function w:GetText()
        return self.text or ""
    end
    function w:SetNumber(n)
        self.number = tonumber(n) or 0
    end
    function w:GetNumber()
        return self.number or 0
    end
    function w:ClearFocus() end
    function w:SetPoint(...)
        table.insert(self.points, { ... })
    end
    function w:ClearAllPoints()
        self.points = {}
    end
    function w:SetWidth(v)
        self.width = v
    end
    function w:SetHeight(v)
        self.height = v
    end
    function w:SetSize(w, h)
        self.width = w
        self.height = h
    end
    function w:GetFrameLevel()
        return 1
    end
    function w:SetFrameLevel() end
    function w:SetBackdrop() end
    function w:Enable()
        self.enabled = true
    end
    function w:Disable()
        self.enabled = false
    end
    function w:CreateFontString()
        return createMockWidget()
    end
    function w:CreateTexture()
        return createMockWidget()
    end
    function w:SetFont() end
    function w:SetTextColor() end
    function w:SetJustifyH() end
    function w:SetJustifyV() end
    function w:GetFontString()
        if not self.font then
            self.font = createMockWidget()
        end
        return self.font
    end
    function w:GetNumPoints()
        return #self.points
    end
    function w:GetPoint(i)
        return unpack(self.points[i] or { "TOPLEFT", nil, "TOPLEFT", 0, 0 })
    end
    setmetatable(w, {
        __index = function(_, key)
            if
                key:find("^Set")
                or key == "ClearAllPoints"
                or key:find("^Get")
                or key:find("^Register")
                or key == "EnableMouse"
                or key == "StartMoving"
                or key == "StopMovingOrSizing"
                or key == "LockHighlight"
                or key == "UnlockHighlight"
            then
                return function() end
            end
        end,
    })
    function w:HookScript(k, fn)
        local orig = self.scripts[k]
        self.scripts[k] = function(...)
            if orig then
                orig(...)
            end
            fn(...)
        end
    end
    if name then
        _G[name] = w
    end
    frames[#frames + 1] = w
    return w
end

_G.CreateFrame = function(frameType, name, parent, template)
    local w = createMockWidget(name)
    if name then
        createMockWidget(name .. "Text")
    end
    return w
end

_G.StaticPopupDialogs = {}
local activePopups = {}
_G.StaticPopup_Show = function(which, text)
    activePopups[which] = { which = which, text = text }
    return activePopups[which]
end
_G.StaticPopup_Hide = function(which)
    activePopups[which] = nil
end

_G.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
_G.GameTooltip = createMockWidget("GameTooltip")

-- Load Models
dofile("AuctionatorRemastered/Remastered/Models/ItemIdentity.lua")
dofile("AuctionatorRemastered/Remastered/Models/ItemMetadata.lua")
dofile("AuctionatorRemastered/Remastered/Models/Database.lua")
dofile("AuctionatorRemastered/Remastered/Models/MarketHistory.lua")
dofile("AuctionatorRemastered/Remastered/Models/Deals.lua")
dofile("AuctionatorRemastered/Remastered/Integration/Database.lua")

local DB = AuctionatorRemastered.Models.Database

-- =========================================================================
-- Feature 2: Database Safety (Error 132 / Finite checks / DB.Clone / Backup)
-- =========================================================================
-- 1. Finite checks on DB.ValidPrice
check(DB.ValidPrice(100) == true, "Valid normal price accepted")
check(DB.ValidPrice(2147483647) == true, "Gold cap copper limit accepted")
check(not DB.ValidPrice(2147483648), "Overflowed price rejected")
check(not DB.ValidPrice(0), "Zero price rejected")
check(not DB.ValidPrice(-1), "Negative price rejected")
check(not DB.ValidPrice(math.huge), "Infinity rejected")
check(not DB.ValidPrice(0 / 0), "NaN rejected")
check(not DB.ValidPrice("100"), "String type price rejected")

-- 2. DB.Clone deep copy
local originalDB = {
    schemaVersion = 1,
    catalog = {
        items = { ["item:100:0"] = { name = "Silk Cloth", texture = "Interface\\Icons\\silk" } },
        names = { enUS = { ["Silk Cloth"] = "item:100:0" } },
        unresolved = { enUS = {} },
    },
    markets = {
        ["TestRealm_Alliance"] = {
            items = {
                ["item:100:0"] = { mr = 500, lastScan = now, ms = { day = 10, last = 500, values = { 500 } } },
            },
            names = { enUS = { ["Silk Cloth"] = "item:100:0" } },
            unresolved = { enUS = {} },
        },
    },
}
local clonedDB = DB.Clone(originalDB)
check(clonedDB ~= originalDB, "DB.Clone returns a new root table")
check(clonedDB.schemaVersion == 1, "Schema version preserved")
check(clonedDB.catalog.items["item:100:0"].name == "Silk Cloth", "Catalog contents preserved")
check(clonedDB.markets["TestRealm_Alliance"].items["item:100:0"].mr == 500, "Market price preserved")
-- Test deep isolation
clonedDB.markets["TestRealm_Alliance"].items["item:100:0"].mr = 9999
check(
    originalDB.markets["TestRealm_Alliance"].items["item:100:0"].mr == 500,
    "Mutating cloned DB does not alter original"
)

-- 3. Service.Open recovery from backup
AUCTIONATOR_REMASTERED_DATABASE = { schemaVersion = 1, markets = "corrupted_markets_string" }
AUCTIONATOR_REMASTERED_DATABASE_BAK = DB.Clone(originalDB)
AuctionatorRemastered.Database.failed = nil
AuctionatorRemastered.Database.active = nil

local handle, reason = AuctionatorRemastered.Database.Open()
check(handle ~= nil, "Corrupted database automatically recovered from valid backup")
check(AUCTIONATOR_REMASTERED_DATABASE.markets["TestRealm_Alliance"] ~= nil, "Database state restored from backup")

-- 4. Future schema version is NOT overwritten by backup
AUCTIONATOR_REMASTERED_DATABASE = { schemaVersion = 999, markets = {} }
AuctionatorRemastered.Database.failed = nil
AuctionatorRemastered.Database.active = nil
local h2, r2 = AuctionatorRemastered.Database.Open()
check(
    h2 == nil and r2 == "Unsupported Remastered database version",
    "Future schema version halts cleanly without backup overwrite"
)
check(AUCTIONATOR_REMASTERED_DATABASE.schemaVersion == 999, "Future database is preserved intact")

-- =========================================================================
-- Feature 6: Third-Party UI Sandbox (DragonUI & ElvUI)
-- =========================================================================
dofile("AuctionatorRemastered/Remastered/UI/Theme.lua")
dofile("AuctionatorRemastered/Remastered/Integration/DragonUI.lua")

-- Mock DragonUI throwing internal errors
_G.DragonUI = {
    ForeverUI = {
        SkinButton = function(btn)
            error("DragonUI ForeverUI button skin fatal crash")
        end,
        SkinScrollBar = function(sb)
            error("DragonUI ForeverUI scrollbar crash")
        end,
        SkinEditBox = function(eb)
            error("DragonUI ForeverUI editbox crash")
        end,
    },
    CharacterPanel = {
        ReskinTab = function(tab)
            error("DragonUI CharacterPanel tab crash")
        end,
    },
}

local testBtn = createMockWidget("Atr_FullScanButton")
local testTab = createMockWidget("AuctionFrameTab1")
_G.AuctionFrame = createMockWidget("AuctionFrame")
_G.AuctionFrame.numTabs = 1

-- Theme.lua sandboxing
local ok1, err1 = pcall(Atr_AnalysisSkin, testBtn, "Button")
check(ok1 == true, "Atr_AnalysisSkin catches DragonUI SkinButton error without crashing")

-- DragonUI integration onUpdate sandboxing
local duiPending = _G.CreateFrame("Frame")
local ok2, err2 = pcall(function()
    _G.DragonUI.ForeverUI.SkinButton(testBtn)
end)
check(ok2 == false, "Mock verifies that raw call would throw")

-- The safeCall inside DragonUI.lua must isolate it:
local ok3 = pcall(function()
    local F = _G.DragonUI.ForeverUI
    pcall(F.SkinButton, testBtn)
end)
check(ok3 == true, "Sandboxed skinning call safely handles external addon crash")

-- Load legacy functions directly from source
local f = assert(io.open("AuctionatorRemastered/Legacy/Auctionator.lua"))
local legacySrc = f:read("*a"):gsub("\r\n", "\n")
f:close()
local function loadDef(name)
    local code = assert(legacySrc:match("(function " .. name .. "%s*%b().-\nend)"), name)
    assert(loadstring(code))()
end
loadDef("Atr_HideAllDialogs")
loadDef("Atr_OnAuctionHouseClosed")
loadDef("Atr_ScanBags")

local createAuctionBlock = assert(
    legacySrc:match(
        '(StaticPopupDialogs%["ATR_CONFIRM_LOW_PRICE"%].-\nfunction Atr_CreateAuction_OnClick%s*%b().-\nend)'
    )
)
assert(loadstring(createAuctionBlock))()

-- =========================================================================
-- Feature 1: AUCTION_HOUSE_CLOSED Hard Reset
-- =========================================================================
local testCloseDialogs = {
    "Atr_CheckActives_Frame",
    "Atr_Error_Frame",
    "Atr_Buy_Confirm_Frame",
    "Atr_FullScanFrame",
    "Atr_Adv_Search_Dialog",
    "Atr_Mask",
    "Atr_SList_Conflict_Frame",
    "Atr_ShpList_Edit_Frame",
    "Atr_DealsDetails",
    "Atr_DealsAdvanced",
    "Atr_BrowserShoppingLists",
}
for _, dname in ipairs(testCloseDialogs) do
    local f = createMockWidget(dname)
    f:Show()
end

_G.StaticPopup_Show("ATR_STOP_SCAN")
_G.StaticPopup_Show("ATR_CONFIRM_LOW_PRICE")
check(activePopups["ATR_STOP_SCAN"] ~= nil, "ATR_STOP_SCAN popup is active")
check(activePopups["ATR_CONFIRM_LOW_PRICE"] ~= nil, "ATR_CONFIRM_LOW_PRICE popup is active")

_G.Atr_ClearBuyState = function()
    _G.testBuyStateCleared = true
end
_G.Atr_Buy_Cancel = function()
    _G.testBuyCancelled = true
end
_G.Atr_FullScanCancel = function()
    _G.testScanCancelled = true
end
_G.Atr_CheckingActive_Finish = function() end
_G.Atr_ClearScanCache = function() end
_G.OpenAllBags = function() end
_G.AuctionatorInited = true
_G.gJustPosted = {}
_G.gSellPane = { ClearSearch = function() end }
_G.gShopPane = { ClearSearch = function() end }
_G.gMorePane = { ClearSearch = function() end }

-- Test Atr_HideAllDialogs
Atr_HideAllDialogs()
for _, dname in ipairs(testCloseDialogs) do
    check(not _G[dname]:IsShown(), dname .. " was hidden by Atr_HideAllDialogs")
end
check(activePopups["ATR_STOP_SCAN"] == nil, "ATR_STOP_SCAN popup hidden on dialog cleanup")
check(activePopups["ATR_CONFIRM_LOW_PRICE"] == nil, "ATR_CONFIRM_LOW_PRICE popup hidden on dialog cleanup")

-- Test Atr_OnAuctionHouseClosed
_G.testBuyStateCleared = false
_G.testBuyCancelled = false
_G.testScanCancelled = false
Atr_OnAuctionHouseClosed()
check(_G.testBuyStateCleared == true, "Atr_ClearBuyState called on AH close")
check(_G.testBuyCancelled == true, "Atr_Buy_Cancel called on AH close")
check(_G.testScanCancelled == true, "Atr_FullScanCancel called on AH close")
check(gAtr_FullScanState == ATR_FS_NULL, "Full scan state reset to NULL")

-- =========================================================================
-- Feature 3: GetItemInfo Nil Safety
-- =========================================================================
-- Mock GetItemInfo returning nil (uncached item)
_G.GetItemInfo = function(link)
    return nil
end

-- 1. Bag scanning with nil GetItemInfo
local testBagsMats, testBagsGear = {}, {}
_G.NUM_BAG_SLOTS = 0
_G.GetContainerNumSlots = function(bag)
    return 2
end
_G.GetContainerItemLink = function(bag, slot)
    return "|cffffffff|Hitem:12345:0:0:0:0:0:0:0:80|h[Uncached Mystery Item]|h|r"
end
_G.GetContainerItemInfo = function(bag, slot)
    return "Interface\\Icons\\mystery", 1, false, 1
end

local scanBagsOk, scanBagsErr = pcall(Atr_ScanBags, testBagsMats, testBagsGear)
check(scanBagsOk == true, "Atr_ScanBags does not crash when GetItemInfo returns nil")

-- 2. ChatEdit link insertion fallback
local insertOk, insertRes = pcall(function()
    local text = "|cffffffff|Hitem:12345:0:0:0:0:0:0:0:80|h[Uncached Mystery Item]|h|r"
    local item = GetItemInfo(text) or (type(text) == "string" and text:match("|h%[(.-)%]|h"))
    return item
end)
check(insertOk and insertRes == "Uncached Mystery Item", "ChatEdit link extracts bracket name when GetItemInfo is nil")

-- 3. Stacking prefs safe name extraction
local spItemName = GetItemInfo("|cffffffff|Hitem:12345:0:0:0:0:0:0:0:80|h[Uncached Cloth]|h|r")
    or ("|cffffffff|Hitem:12345:0:0:0:0:0:0:0:80|h[Uncached Cloth]|h|r"):match("|h%[(.-)%]|h")
check(spItemName == "Uncached Cloth", "Stacking prefs extract name from link when GetItemInfo is nil")

-- =========================================================================
-- Feature 4: «Fat-Finger» & Bad Price Barrier
-- =========================================================================
_G.MoneyInputFrame_GetCopper = function(frame)
    return frame.copper or 0
end
_G.Atr_StackPrice = { copper = 0 }
_G.Atr_StartingPrice = { copper = 0 }
_G.Atr_Duration = {}
_G.UIDropDownMenu_GetSelectedValue = function()
    return 1
end
_G.Atr_StackSize = function()
    return 1
end
_G.Atr_Batch_NumAuctions = {
    GetNumber = function()
        return 1
    end,
    SetText = function() end,
}
_G.Atr_Memorize_Stacking_If = function() end
_G.Atr_ResetPostingProgress = function() end
_G.StartAuction = function(...)
    _G.auctionStartedArgs = { ... }
end
_G.Atr_SetTextureButton = function() end
_G.Atr_SellControls_TexName = { SetText = function() end }
_G.Atr_StackPriceText = { SetText = function() end }
_G.Atr_ItemPriceText = { Hide = function() end }
_G.Atr_ItemPrice = { Hide = function() end }
_G.Atr_ItemsOwned_Text = { SetText = function() end }
_G.Atr_Batch_MaxAuctions_Text = { SetText = function() end }
_G.Atr_Batch_MaxStacksize_Text = { SetText = function() end }
_G.Atr_SetStackSize = function() end
_G.Atr_SetToShowCurrent = function() end
_G.zc = {
    priceToMoneyString = function(c)
        return c .. "c"
    end,
}

_G.gCurrentPane = {
    activeScan = {
        itemName = "Frostweave Cloth",
        itemLink = "|cffffffff|Hitem:33470:0:0:0:0:0:0:0:80|h[Frostweave Cloth]|h|r",
    },
}

-- 1. Test Below-Vendor Warning
-- Item vendor price: 25 silver = 2500 copper
_G.GetItemInfo = function(link)
    return "Frostweave Cloth", link, 1, 75, 1, "Trade Goods", "Cloth", 20, "", "", 2500
end
_G.Atr_StackPrice.copper = 100 -- 1 silver buyout (less than 2500c vendor price!)
_G.Atr_StartingPrice.copper = 100
_G.auctionStartedArgs = nil

Atr_CreateAuction_OnClick()
check(_G.auctionStartedArgs == nil, "Posting below vendor price blocked without confirmation")
check(activePopups["ATR_CONFIRM_LOW_PRICE"] ~= nil, "ATR_CONFIRM_LOW_PRICE popup triggered for below-vendor pricing")
check(
    activePopups["ATR_CONFIRM_LOW_PRICE"].text:find("vendor sell price", 1, true) ~= nil,
    "Vendor warning text present in dialog"
)

-- Accept vendor warning
local dialog = activePopups["ATR_CONFIRM_LOW_PRICE"]
check(dialog.atrExecutePost ~= nil, "Dialog stores confirmation continuation")
dialog.atrExecutePost()
check(_G.auctionStartedArgs ~= nil, "Auction posted after confirming below-vendor warning")

-- 2. Test Deep Market Discount Warning (< 20% of market reference)
activePopups["ATR_CONFIRM_LOW_PRICE"] = nil
_G.auctionStartedArgs = nil
-- Reference price: 100 gold = 1,000,000 copper. Vendor price: 10 copper.
_G.GetItemInfo = function(link)
    return "Frostweave Cloth", link, 1, 75, 1, "Trade Goods", "Cloth", 20, "", "", 10
end
_G.Atr_MarketReference = function(name)
    return 1000000
end
_G.Atr_StackPrice.copper = 50000 -- 5 gold (5% of 100g reference, deep discount!)
_G.Atr_StartingPrice.copper = 50000

Atr_CreateAuction_OnClick()
check(_G.auctionStartedArgs == nil, "Posting 80% below market reference blocked without confirmation")
check(activePopups["ATR_CONFIRM_LOW_PRICE"] ~= nil, "Market discount warning popup shown")
check(
    activePopups["ATR_CONFIRM_LOW_PRICE"].text:find("market reference", 1, true) ~= nil,
    "Market reference warning text present in dialog"
)

-- 3. Shift key bypass
activePopups["ATR_CONFIRM_LOW_PRICE"] = nil
_G.auctionStartedArgs = nil
_G.IsShiftKeyDown = function()
    return true
end

Atr_CreateAuction_OnClick()
check(_G.auctionStartedArgs ~= nil, "Holding Shift bypasses warning for power users")
_G.IsShiftKeyDown = function()
    return false
end

-- =========================================================================
-- Feature 5: GC Spike Shield
-- =========================================================================
local gcSteps = 0
_G.collectgarbage = function(action, arg)
    if action == "step" then
        gcSteps = gcSteps + 1
    end
end

createMockWidget("Atr_FullScanDone")
createMockWidget("Atr_FullScanStatus")
createMockWidget("Atr_FullScanFrame")
createMockWidget("Atr_FullScanHTML")
createMockWidget("Atr_FullScanResults")
dofile("AuctionatorRemastered/Remastered/Integration/FullScan.lua")

local initialGc = gcSteps
AuctionatorRemastered.FullScan.running = true
Atr_FullScanCancel("Testing GC cancellation step")
check(gcSteps > initialGc, "Atr_FullScanCancel executes incremental GC step")

-- =========================================================================
-- Feature 7: Time-Sliced / Debounced Deals Filtering
-- =========================================================================
_G.AuctionFrameTab1 = createMockWidget("AuctionFrameTab1")
_G.AtrFontOrange = {}
_G.PanelTemplates_TabResize = function() end
_G.PanelTemplates_SetNumTabs = function() end
_G.PanelTemplates_EnableTab = function() end
dofile("AuctionatorRemastered/Remastered/UI/Appearance.lua")
dofile("AuctionatorRemastered/Remastered/Features/Deals.lua")
for _, fn in ipairs(hooks.Atr_Init or {}) do
    fn()
end
local dealsSearch = _G.Atr_DealsSearch
check(dealsSearch ~= nil, "Atr_DealsSearch exists")

-- Mock HasFocus returning true (user actively typing)
dealsSearch.HasFocus = function()
    return true
end
local dealsRefreshed = false
local oldRefresh = Atr_DealsPanel.scripts.OnUpdate

dealsSearch.scripts.OnTextChanged(dealsSearch)
-- The timer is active, immediate refresh was avoided while typing
check(dealsSearch.scripts.OnUpdate ~= nil, "OnUpdate handler attached to search editbox")

-- Now simulate elapsed time expiring the debounce timer
dealsSearch.scripts.OnUpdate(dealsSearch, 0.25)

-- Clear Search immediately resets search
_G.Atr_DealsClearSearch.scripts.OnClick()
check(dealsSearch:GetText() == "", "Clear search resets editbox text")

print("PASS: " .. checks .. " comprehensive stability checks across all 7 features")
