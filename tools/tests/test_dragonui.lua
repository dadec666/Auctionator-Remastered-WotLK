-- DragonUI 3.0 Integration unit tests for Auctionator Remastered
local checks = 0
local function check(value, label)
    checks = checks + 1
    assert(value, label)
end

hooksecurefunc = hooksecurefunc or function() end
local createdFrames = {}
CreateFrame = CreateFrame or function(kind, name, parent)
    local f = {
        name = name,
        scripts = {},
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        SetScript = function(self, k, fn) self.scripts[k] = fn end,
        GetScript = function(self, k) return self.scripts[k] end,
        HookScript = function(self, k, fn)
            local old = self.scripts[k]
            self.scripts[k] = function(...) if old then old(...) end; fn(...) end
        end,
    }
    createdFrames[#createdFrames + 1] = f
    return f
end

-- Mock DragonUI
local skinnedButtons = {}
local skinnedCheckBoxes = {}
local skinnedEditBoxes = {}
local skinnedScrollBars = {}
local reskinnedTabs = {}

local mockDragonUI = {
    ForeverUI = {
        SkinButton = function(btn)
            skinnedButtons[btn] = true
            btn._fuSkinned = true
        end,
        SkinCheckButton = function(cb)
            skinnedCheckBoxes[cb] = true
            cb._fuSkinned = true
        end,
        SkinEditBox = function(eb)
            skinnedEditBoxes[eb] = true
            eb._fuSkinned = true
        end,
        SkinScrollBar = function(sb)
            skinnedScrollBars[sb] = true
            sb._fuSkinned = true
        end,
    },
    CharacterPanel = {
        ReskinTab = function(tab, onTop)
            reskinnedTabs[tab] = { onTop = onTop }
            tab._duiSkinned = true
        end,
    },
    IsModuleEnabled = function(self, mod)
        return mod == "darkmode"
    end,
    GetModuleConfig = function(self, mod)
        if mod == "darkmode" then
            return { intensity_preset = 3 }
        end
    end,
}

_G.DragonUI = mockDragonUI

-- Load Theme.lua and DragonUI.lua
assert(loadfile("AuctionatorRemastered/Remastered/UI/Theme.lua"))()

-- Test Atr_AnalysisSkin delegating to DragonUI
local mockBtn = { name = "MockButton" }
Atr_AnalysisSkin(mockBtn, "Button")
check(skinnedButtons[mockBtn], "Atr_AnalysisSkin skins buttons via DragonUI ForeverUI")

local mockClose = { name = "MockCloseButton" }
Atr_AnalysisSkin(mockClose, "CloseButton")
check(skinnedButtons[mockClose], "Atr_AnalysisSkin skins close buttons via DragonUI ForeverUI")

local mockCb = { name = "MockCheckBox" }
Atr_AnalysisSkin(mockCb, "CheckBox")
check(skinnedCheckBoxes[mockCb], "Atr_AnalysisSkin skins checkbuttons via DragonUI ForeverUI")

local mockEb = { name = "MockEditBox" }
Atr_AnalysisSkin(mockEb, "EditBox")
check(skinnedEditBoxes[mockEb], "Atr_AnalysisSkin skins editboxes via DragonUI ForeverUI")

local mockSb = { name = "MockScrollBar" }
Atr_AnalysisSkin(mockSb, "ScrollBar")
check(skinnedScrollBars[mockSb], "Atr_AnalysisSkin skins scrollbars via DragonUI ForeverUI")

-- Test Atr_NativeSurface under DragonUI and DarkMode
local backdropSet, backdropColor, borderColor
local mockFrame = {
    SetBackdrop = function(self, bd) backdropSet = bd end,
    SetBackdropColor = function(self, r, g, b, a) backdropColor = { r, g, b, a } end,
    SetBackdropBorderColor = function(self, r, g, b, a) borderColor = { r, g, b, a } end,
}

local ok = Atr_NativeSurface(mockFrame, "body", 1)
check(ok == true, "Atr_NativeSurface handles DragonUI frames")
check(backdropSet and backdropSet.bgFile == "Interface\\Buttons\\WHITE8X8", "Backdrop set with WHITE8X8")
check(backdropColor and backdropColor[4] == 1, "Backdrop color applied")
check(borderColor and #borderColor == 4, "Border color applied with DarkMode tint")

-- Test DragonUI.lua execution
AuctionatorRemastered = {
    Legacy = {
        Hook = function(name, fn) end,
    },
}

Atr_FullScanButton = { name = "Atr_FullScanButton" }
Atr_Buy1_Button = { name = "Atr_Buy1_Button" }
AuctionFrame = {
    numTabs = 3,
    IsShown = function() return true end,
    HookScript = function() end,
}
AuctionFrameTab1 = { name = "AuctionFrameTab1" }
AuctionFrameTab2 = { name = "AuctionFrameTab2" }
AuctionFrameTab3 = { name = "AuctionFrameTab3" }
Atr_ListTabsTab1 = { name = "Atr_ListTabsTab1" }
Atr_Buy_Confirm_Numstacks = { name = "Atr_Buy_Confirm_Numstacks" }
AuctionatorScrollFrame = { name = "AuctionatorScrollFrame" }

assert(loadfile("AuctionatorRemastered/Remastered/Integration/DragonUI.lua"))()

-- Trigger pending OnUpdate
local pendingFrame = createdFrames[#createdFrames]
check(pendingFrame ~= nil and pendingFrame.scripts.OnUpdate ~= nil, "DragonUI pending frame created with OnUpdate")
pendingFrame.scripts.OnUpdate(pendingFrame)

check(skinnedButtons[Atr_FullScanButton], "Atr_FullScanButton skinned by DragonUI integration")
check(skinnedButtons[Atr_Buy1_Button], "Atr_Buy1_Button skinned by DragonUI integration")
check(reskinnedTabs[AuctionFrameTab1], "AuctionFrameTab1 reskinned by DragonUI tabs module")
check(reskinnedTabs[Atr_ListTabsTab1] and reskinnedTabs[Atr_ListTabsTab1].onTop == true, "Atr_ListTabsTab1 reskinned as onTop tab")
check(skinnedEditBoxes[Atr_Buy_Confirm_Numstacks], "Atr_Buy_Confirm_Numstacks editbox skinned")
check(skinnedScrollBars[AuctionatorScrollFrame], "AuctionatorScrollFrame scrollbar skinned")

-- Clean up
_G.DragonUI = nil
print("PASS: " .. checks .. " DragonUI 3.0 button, tab, input, scrollbar, DarkMode and lifecycle checks")
