dofile("AuctionatorRemastered/Remastered/Core/Bootstrap.lua")
dofile("AuctionatorRemastered/Remastered/Integration/LegacyBridge.lua")
-- Run from repository root: lua5.1 tools/tests/test_browser_link_input.lua
local function source(path)
    local file=assert(io.open(path,'rb'));local data=file:read('*a');file:close();return data:gsub('\r\n','\n')
end
local browser=source('AuctionatorRemastered/Remastered/Features/Browser.lua')
local main=source('AuctionatorRemastered/Legacy/Auctionator.lua')
local focused,shown,shift,mouse=true,true,true,false
local search={};local filters=0;local registered=0;local skilletCallback
local window={scripts={}}
local earlyChat,earlyModified,earlySplit=0,0,0
ChatEdit_InsertLink=function() earlyChat=earlyChat+1;return 'early chat' end
HandleModifiedItemClick=function() earlyModified=earlyModified+1;return 'early modified' end
ContainerFrameItemButton_OnModifiedClick=function() earlySplit=earlySplit+1;return 'early split' end
function window:IsShown() return shown end
function window:SetScript(event,callback) self.scripts[event]=callback end
function search:HasFocus() return focused end
function search:SetText(value) self.text=value end
function search:HighlightText() end
function search:ClearFocus() focused=false end
function IsShiftKeyDown() return shift end
function IsMouseButtonDown() return mouse end
function MouseIsOver() return false end
function CreateFrame() return {RegisterEvent=function() end,SetScript=function() end} end
Skillet={SetSelectedSkill=function() end}
function hooksecurefunc(object,name,callback) registered=registered+1;skilletCallback=callback end
function GetItemInfo(link) if link:find('item:1:',1,true) then return 'Linen Cloth' end end
function GetSpellInfo(id) if id==3 then return 'Glyph of Test' end end
function GetTradeSkillItemLink() return '|cffffffff|Hitem:1:0|h[Linen Cloth]|h|r' end
local first=assert(browser:find('function Atr_InsertBrowserSearchLink',1,true))
local last=assert(browser:find('local function createWindow()',first,true))
local code=browser:sub(first,last-1)
local binding=assert(loadstring('return function(window,search,applyFilters)\nlocal selectedClass,selectedSubclass="Armor","Plate"\nlocal searchLinkTarget=false\n'..code..'\nreturn function() return selectedClass,selectedSubclass end, function(value) searchLinkTarget=value end end'))()
local categories,arm=binding(window,search,function() filters=filters+1 end)
local n=0
local function check(ok,message) n=n+1;assert(ok,message) end
check(registered==1,'Skillet hook installed once')
-- Fresh login: no AH globals, no Auctionator late hooks and no open chat.
AuctionFrame=nil
local earlySlot={GetID=function() return 7 end,GetParent=function() return {GetID=function() return 2 end} end}
function GetContainerItemLink() return GetTradeSkillItemLink() end
check(ChatEdit_InsertLink(GetTradeSkillItemLink())==true and earlyChat==0,'chat-link route works before first AH visit')
check(HandleModifiedItemClick(GetTradeSkillItemLink())==true and earlyModified==0,'profession icon route works before first AH visit')
check(ContainerFrameItemButton_OnModifiedClick(earlySlot,'LeftButton')==true and earlySplit==0,'bag route works before first AH visit, without splitting')
local installed=ContainerFrameItemButton_OnModifiedClick
Atr_InstallBrowserLinkHooks()
check(installed==ContainerFrameItemButton_OnModifiedClick,'addon-load retries do not wrap hooks twice')
focused=false;arm(true)
check(ContainerFrameItemButton_OnModifiedClick(earlySlot,'LeftButton')==true,'shift mouse-down may drop focus before the bag click')
local otherInput={}
GetCurrentKeyboardFocus=function() return otherInput end
check(not Atr_InsertBrowserSearchLink(GetTradeSkillItemLink()),'retained target never steals input from another edit box')
GetCurrentKeyboardFocus=nil;arm(false);focused=true
filters=0
check(Atr_InsertBrowserSearchLink(GetTradeSkillItemLink()) and search.text=='Linen Cloth','cached item becomes plain search name')
check(categories()==nil and filters==1,'linked search clears restrictive category and updates results')
check(Atr_InsertBrowserSearchLink('|Hitem:2:0|h[Uncached Bag]|h') and search.text=='Uncached Bag','uncached item falls back to linked name')
check(Atr_InsertBrowserSearchLink('|Henchant:3|h[Recipe]|h') and search.text=='Glyph of Test','profession recipe resolves spell name')
check(not Atr_InsertBrowserSearchLink('|Hquest:1|h[Quest]|h') and not Atr_InsertBrowserSearchLink(nil),'unrelated/missing links ignored')
focused=false;check(Atr_InsertBrowserSearchLink(GetTradeSkillItemLink()),'unfocused visible browser accepts shift-linked items')
focused=true;shown=false;check(not Atr_InsertBrowserSearchLink(GetTradeSkillItemLink()),'hidden browser does not consume links')
shown=true;shift=false;check(not Atr_InsertBrowserSearchLink(GetTradeSkillItemLink()),'ordinary clicks are unaffected')
shift=true;local before=filters
skilletCallback(Skillet,1,false);check(filters==before,'programmatic Skillet selection ignored')
skilletCallback(Skillet,1,true);check(filters==before+1 and search.text=='Linen Cloth','Skillet recipe click works without opening chat')
shown=false;focused=false
local dealVisible,logsVisible=true,false
Atr_DealsPanel={IsShown=function() return dealVisible end}
Atr_TradingLogs={IsShown=function() return logsVisible end}
Atr_DealsSearch={SetText=function(self,value) self.text=value end,HighlightText=function() end}
Atr_LogsSearch={SetText=function(self,value) self.text=value end,HighlightText=function() end}
check(ChatEdit_InsertLink(GetTradeSkillItemLink())==true and Atr_DealsSearch.text=='Linen Cloth','Deals accepts shift-link without search focus')
dealVisible=false;logsVisible=true
check(ContainerFrameItemButton_OnModifiedClick(earlySlot,'LeftButton')==true and Atr_LogsSearch.text=='Linen Cloth','Logs accepts bag shift-click without search focus')
GetCurrentKeyboardFocus=function() return otherInput end
check(not Atr_InsertBrowserSearchLink(GetTradeSkillItemLink()),'visible Logs does not steal an active chat or other edit box')
GetCurrentKeyboardFocus=nil;logsVisible=false;shown=true;focused=true
local updateStart = assert(browser:find("local wasMouseDown = false"))
local updateEnd = assert(browser:find('window:SetScript%("OnHide"', updateStart))
assert(loadstring('return function(window,search)\n'..browser:sub(updateStart,updateEnd-1)..'\nend'))()(window,search)
mouse=true;window.scripts.OnUpdate();check(focused,'shift-click outside preserves search focus until link insertion')
mouse=false;window.scripts.OnUpdate();shift=false;mouse=true;window.scripts.OnUpdate()
check(not focused,'ordinary click outside still releases focus for movement')
-- Verify the existing ChatEdit_InsertLink override prioritizes the browser,
-- then retains the old chat/Buy behavior when it is not the active input.
local chat,buy=0,0
local wrapper=assert(main:match('(function auctionator_ChatEdit_InsertLink%b().-\nend)'))
assert(loadstring('return function(original)\nlocal auctionator_orig_ChatEdit_InsertLink=original\n'..wrapper..'\nend'))()(function() chat=chat+1;return 'chat' end)
AuctionFrame={IsShown=function() return true end};BUY_TAB=4
function Atr_IsTabSelected() return true end
strfind=string.find
function Atr_SetSearchText() buy=buy+1 end
function Atr_Search_Onclick() end
focused=true;shift=true
check(auctionator_ChatEdit_InsertLink(GetTradeSkillItemLink())==true and chat==0 and buy==0,'browser input takes precedence over live Buy search')
focused=false;shown=false
check(auctionator_ChatEdit_InsertLink(GetTradeSkillItemLink())==true and buy==1,'existing Buy shortcut preserved')
AuctionFrame.IsShown=function() return false end
check(auctionator_ChatEdit_InsertLink(GetTradeSkillItemLink())=='chat' and chat==1,'ordinary chat insertion preserved')
-- Bag slots may enter stack-splitting without attempting chat insertion.
local bagHandler=assert(main:match('(function Atr_ContainerFrameItemButton_OnModifiedClick %b().-\nend)'))
local delegated=0
assert(loadstring('return function(original)\nlocal auctionator_orig_ContainerFrameItemButton_OnModifiedClick=original\n'..bagHandler..'\nend'))()(function() delegated=delegated+1;return 'original' end)
AUCTIONATOR_ENABLE_ALT=0
local bagID,slotID
function GetContainerItemLink(bag,slot) bagID,slotID=bag,slot;return GetTradeSkillItemLink() end
local slot={GetID=function() return 7 end,GetParent=function() return {GetID=function() return 2 end} end}
shown=true;focused=true;shift=true
check(Atr_ContainerFrameItemButton_OnModifiedClick(slot,'LeftButton')==true and delegated==0 and search.text=='Linen Cloth','bag shift-click consumed before stack splitting')
check(bagID==2 and slotID==7,'bag and slot IDs read from standard/ElvUI container buttons')
focused=false;shown=false
check(Atr_ContainerFrameItemButton_OnModifiedClick(slot,'LeftButton')=='original' and delegated==1,'hidden browser preserves original stack splitting')
focused=true;shift=false
check(Atr_ContainerFrameItemButton_OnModifiedClick(slot,'LeftButton')=='original' and delegated==2,'ordinary bag click preserved')
shift=true
check(Atr_ContainerFrameItemButton_OnModifiedClick(slot,'RightButton')=='original' and delegated==3,'shift right-click preserved')
-- Visiting AH later wraps the early hooks; both layers must still delegate
-- correctly, without recursion or double insertion.
assert(loadstring('return function(original)\nlocal auctionator_orig_ChatEdit_InsertLink=original\n'..wrapper..'\nend'))()(ChatEdit_InsertLink)
focused=false
check(auctionator_ChatEdit_InsertLink(GetTradeSkillItemLink())=='early chat' and earlyChat==1,'later AH hook delegates safely through early chat hook')
assert(loadstring('return function(original)\nlocal auctionator_orig_ContainerFrameItemButton_OnModifiedClick=original\n'..bagHandler..'\nend'))()(installed)
check(Atr_ContainerFrameItemButton_OnModifiedClick(slot,'LeftButton')=='early split' and earlySplit==1,'later AH hook preserves normal stack splitting')
print('PASS: '..n..' browser link input, focus, profession and chat routing checks')
