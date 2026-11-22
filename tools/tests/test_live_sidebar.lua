dofile("AuctionatorRemastered/Remastered/Core/Bootstrap.lua")
dofile("AuctionatorRemastered/Remastered/Integration/LegacyBridge.lua")
-- Shared Buy/Undercuts sidebar: native scroll gutter, backdrop and row bounds.
local hooks,driver={},nil
function hooksecurefunc(name,fn) hooks[name]=fn end
local function widget(name)
 local w={name=name,shown=true,width=172,height=252,points={}}
 if name then _G[name]=w end
 function w:GetName() return self.name end
 function w:GetFrameLevel() return self.level or 1 end
 function w:SetFrameLevel(level) self.level=level end
 function w:EnableMouse(value) self.mouse=value end
 function w:IsShown() return self.shown end
 function w:Show() self.shown=true end
 function w:Hide() self.shown=false end
 function w:GetWidth() return self.width end
 function w:GetHeight() return self.height end
 function w:SetWidth(v) self.width=v end
 function w:SetHeight(v) self.height=v end
 function w:SetSize(x,y) self.width=x;self.height=y end
 function w:ClearAllPoints() self.points={} end
 function w:SetPoint(...) table.insert(self.points,{...}) end
 function w:RegisterEvent() end
 function w:SetScript(event,fn) self[event]=fn end
 function w:GetRegions() return unpack(self.regions or {}) end
 function w:GetObjectType() return 'Texture' end
 function w:GetTexture() return self.texture end
 function w:SetTexture(value) self.texture=value end
 function w:SetBackdrop(v) self.backdrop=v end
 function w:SetBackdropColor(...) self.color={...} end
 function w:GetBackdropColor() return unpack(self.color) end
 function w:CreateTexture() return widget() end
 function w:SetVertexColor(...) self.vertex={...} end
 function w:SetBackdropBorderColor() end
 function w:SetJustifyH() end
 return w
end
function CreateFrame(_,_,parent) local frame=widget();frame.parent=parent;if not parent then driver=frame end;return frame end
local buying=true
function Atr_IsTabSelected(id) return id==3 and buying end
AuctionFrame=widget('AuctionFrame');Atr_Main_Panel=widget('Atr_Main_Panel')
Atr_Hlist=widget('Atr_Hlist');Atr_Hlist_ScrollFrame=widget('Atr_Hlist_ScrollFrame')
Atr_Hlist_ScrollFrame.offset=7
local vertical=function() error('styling must not execute a scroll action') end
Atr_Hlist_ScrollFrame.OnVerticalScroll=vertical
local divider,other=widget(),widget();divider.width=92;divider.texture='Interface\\Tooltips\\UI-Tooltip-Border'
other.texture='unrelated-decoration';Atr_Hlist.regions={divider,other}
for _,suffix in ipairs({'ScrollBar','ScrollBarScrollUpButton','ScrollBarScrollDownButton'}) do widget('Atr_Hlist_ScrollFrame'..suffix) end
local clicks={}
for i=1,20 do
 local row=widget('AuctionatorHEntry'..i);widget('AuctionatorHEntry'..i..'_EntryText')
 row.OnClick=function() end;clicks[i]=row.OnClick
end
local function read(path) local f=assert(io.open(path));local s=f:read('*a');f:close();return s end
dofile('AuctionatorRemastered/Remastered/UI/Theme.lua')

assert(loadfile('AuctionatorRemastered/Remastered/Integration/ElvUI.lua'))()
local checks=0
local function check(v,label) checks=checks+1;assert(v,label) end
-- Standard UI must receive the correction, too (the old scheduler was ElvUI-only).
ElvUI=nil;hooks.Atr_AuctionFrameTab_OnClick()
check(driver:IsShown(),'vanilla tab changes schedule sidebar styling')
driver.OnUpdate(driver)
check(not divider:IsShown() and divider.texture==nil and other:IsShown(),'stretched XML divider asset is permanently removed regardless of resolved width')
local surface=Atr_Hlist.atrListSurface
check((surface.backdrop.bgFile=='Interface\\Buttons\\WHITE8X8' or surface.backdrop.bgFile=='Interface\\Tooltips\\UI-Tooltip-Background') and not Atr_Hlist.backdrop,'only the outer surface has a border; content/gutter divider is removed')
check(surface.color[4]==1,'sidebar remains opaque and readable')
local gutter=surface
check(gutter and gutter.points[1][3]=='TOPLEFT' and gutter.points[2][4]==24 and gutter.color[4]==1,'opaque vanilla background extends behind the complete scroll gutter')
local bar=Atr_Hlist_ScrollFrameScrollBar
check(bar.width==18 and bar.points[1][2]==Atr_Hlist and bar.points[1][3]=='TOPRIGHT' and bar.points[1][4]==3,'scrollbar occupies an external compact gutter')
check(Atr_Hlist_ScrollFrame.points[2][2]==Atr_Hlist,'scroll viewport follows content bounds')
for i=1,15 do
 local row=_G['AuctionatorHEntry'..i]
 check(row.width==164 and -row.points[1][5]+row.height<=252,'Buy row '..i..' stays inside list and clear of scrollbar')
end
-- Short ElvUI Undercuts viewport: retain all 20 rows and original scroll logic.
buying=false;Atr_Hlist.height=314
local skins=0
ElvUI={{GetModule=function() return {HandleScrollBar=function(_,b) skins=skins+1;b:ClearAllPoints();b:SetPoint('CENTER') end} end,media={backdropfadecolor={.1,.12,.14,.6}}}}
hooks.Atr_AuctionFrameTab_OnClick();driver.OnUpdate(driver)
check(skins==1 and bar.points[1][3]=='TOPRIGHT','ElvUI native scrollbar skin applied before gutter anchors')
check(surface.color[1]==.1 and surface.color[4]==1,'ElvUI theme colors used with opaque background')
check(gutter.color[1]==.1 and gutter.color[2]==.12,'gutter matches the ElvUI list background')
bar:Hide()
check(gutter:IsShown(),'gutter remains filled when no scrollbar is needed')
for i=1,20 do
 local row=_G['AuctionatorHEntry'..i]
 check(-row.points[1][5]+row.height<=314 and row.OnClick==clicks[i],'Undercuts row '..i..' fits and retains click handler')
end
check(Atr_Hlist_ScrollFrame.offset==7 and Atr_Hlist_ScrollFrame.OnVerticalScroll==vertical,'styling preserves scroll offset and original callback')
-- Restyling never mistakes the new border for the original XML divider.
local themedEdge=widget();themedEdge.width=5;themedEdge.texture='Interface\\Tooltips\\UI-Tooltip-Border'
Atr_Hlist.regions={divider,themedEdge};driver.OnUpdate(driver)
check(themedEdge:IsShown(),'new theme border survives repeated styling')
print('PASS: '..checks..' native/ElvUI sidebar background, gutter, row bounds and callback checks')
