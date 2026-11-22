dofile("AuctionatorRemastered/Remastered/Core/Bootstrap.lua")
dofile("AuctionatorRemastered/Remastered/Integration/LegacyBridge.lua")
-- lua5.1 tools/tests/test_browser_tree.lua
local function read(path) local f=assert(io.open(path));local s=f:read('*a');f:close();return s end
local checks=0
local function check(value,message) checks=checks+1;assert(value,message) end
local widgets={}
local function widget(name,parent)
 local w={name=name,parent=parent,shown=true,scripts={},points={},width=980,height=575}
 widgets[#widgets+1]=w;if name then _G[name]=w end
 function w:SetScript(k,fn) self.scripts[k]=fn end
 function w:HookScript(k,fn) local prev=self.scripts[k];self.scripts[k]=function(...) if prev then prev(...) end;fn(...) end end
 function w:Show() local changed=not self.shown;self.shown=true;if changed and self.scripts.OnShow then self.scripts.OnShow(self) end end
 function w:Hide() local changed=self.shown;self.shown=false;if changed and self.scripts.OnHide then self.scripts.OnHide(self) end end
 function w:IsShown() return self.shown end
 function w:SetText(value) self.text=tostring(value);if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end end
 function w:GetText() return self.text or '' end
 function w:SetChecked(value) self.checked=value end
 function w:GetChecked() return self.checked end
 function w:GetFontString() if not self.font then self.font=widget(nil,self) end;return self.font end
 function w:SetPoint(...) self.points[#self.points+1]={...} end
 function w:ClearAllPoints() self.points={} end
 function w:SetSize(x,y) self.width=x;self.height=y end
 function w:SetWidth(n) self.width=n end
 function w:SetHeight(n) self.height=n end
 function w:GetWidth() return self.width end
 function w:GetHeight() return self.height end
 function w:GetFrameLevel() return self.level or 1 end
 function w:SetFrameLevel(n) self.level=n end
 function w:SetScale(n) self.scale=n end
 function w:SetBackdrop(data) self.backdrop=data end
 function w:SetBackdropColor(...) self.backdropColor={...} end
 function w:SetTexture(...) self.textureArgs={...} end
 function w:SetTextColor(...) self.textColor={...} end
 function w:CreateFontString() return widget(nil,self) end
 function w:CreateTexture() return widget(nil,self) end
 function w:GetName() return self.name end
 function w:SetVerticalScroll(n) self.offset=n end
 function w:ClearFocus() self.focus=false end
 function w:HasFocus() return self.focus end
 function w:LockHighlight() self.locked=true end
 function w:UnlockHighlight() self.locked=false end
 function w:Enable() self.enabled=true end
 function w:Disable() self.enabled=false end
 for _,method in ipairs({'SetAllPoints','RegisterEvent','SetFrameStrata','SetClampedToScreen','EnableMouse','SetMovable','RegisterForDrag','StartMoving','StopMovingOrSizing','SetBackdropColor','SetBackdropBorderColor','SetNormalFontObject','SetHighlightFontObject','SetHighlightTexture','SetTexture','SetAlpha','SetVertexColor','SetTextColor','SetHeight','SetJustifyH','SetSpacing','SetTexCoord','SetAutoFocus','RegisterForClicks','SetOwner','AddLine','SetHyperlink'}) do
  if not w[method] then w[method]=function() end end
 end
 return w
end
function CreateFrame(_,name,parent,template)
 local w=widget(name,parent)
 if template=='FauxScrollFrameTemplate' and name then
  local bar=widget(name..'ScrollBar',w)
  widget(name..'ScrollBarScrollUpButton',bar);widget(name..'ScrollBarScrollDownButton',bar)
 end
 return w
end
function FauxScrollFrame_Update(w,count,visible) w.count=count;w.visible=visible end
function FauxScrollFrame_GetOffset(w) return w.offset or 0 end
function FauxScrollFrame_SetOffset(w,n) w.offset=n end
function FauxScrollFrame_OnVerticalScroll(w,n,step,fn) w.offset=math.floor(n/step);fn() end
function UIDropDownMenu_Initialize() end
local hooks={}
function hooksecurefunc(name,fn) hooks[name]=fn end
function CloseDropDownMenus() end
function IsShiftKeyDown() return false end
function IsMouseButtonDown() return false end
function MouseIsOver() return false end
function GetRealmName() return 'Test Realm' end
function UnitFactionGroup() return 'Alliance' end
function GetItemInfo() end
function time() return 100000 end
function date(_,stamp) return tostring(stamp) end
function Atr_MarketPercentText() return '50%' end
function Atr_GetMarketHistoryDays() return 14 end
function QueryAuctionItems() error('offline UI must not query AH') end
function LoadAddOn() error('offline UI must not load Auction UI') end
UIParent=widget();UIParent.width=1280;UIParent.height=800
GameTooltip=widget();UISpecialFrames={};StaticPopupDialogs={};SlashCmdList={}
ITEM_QUALITY_COLORS={[1]={r=1,g=1,b=1}};gAtrZC={priceToMoneyString=tostring}
gAtr_ScanDB={};AuctionFrame=nil
dofile('AuctionatorRemastered/Remastered/UI/Theme.lua')
dofile('AuctionatorRemastered/Remastered/Data/BrowserData.lua')
dofile('AuctionatorRemastered/Remastered/Models/BrowserCategories.lua')
assert(loadfile('AuctionatorRemastered/Remastered/Features/Browser.lua'))()
AUCTIONATOR_BROWSER_ITEMS={CachedHood={class='Armor',subclass='Cloth',equipLoc='INVTYPE_HEAD',texture='saved-icon',link='item:123'}}
local shared=Atr_GetBrowserItemMetadata('CachedHood',{})
check(shared.class=='Armor' and shared.subclass=='Cloth' and shared.equipLoc=='INVTYPE_HEAD','Deals metadata shares the browser cached equipment classification')
check(shared.link=='item:123' and shared.texture=='saved-icon','shared metadata preserves exact cached identity and icon')
local missing=Atr_GetBrowserItemMetadata('Missing',{cc=2})
check(missing.class=='Armor' and not missing.equipLoc,'missing slot metadata stays unknown without losing the saved class')
check(Atr_GetBrowserItemMetadata('Unknown').class=='Unclassified','shared metadata safely handles missing saved items')
local incompleteSample={
 {name='Hood',class='Armor',subclass='Cloth',equipLoc='INVTYPE_HEAD'},
 {name='Missing slot',class='Armor',subclass='Mail'},
 {name='Missing category',class='Unclassified'},
 {name='Missing subclass',class='Weapon',equipLoc='INVTYPE_WEAPON'},
 {name='Herb',class='Trade Goods',subclass='Herb'},
}
AUCTIONATOR_BROWSER_SETTINGS={}
local complete=Atr_FilterIncompleteBrowserItems(incompleteSample)
check(#complete==2 and complete[1].name=='Hood' and complete[2].name=='Herb','default hides missing categories and equipment slots but keeps non-equipment without slots')
check(#incompleteSample==5,'visibility filter preserves the original items and saved data')
AUCTIONATOR_BROWSER_SETTINGS.showIncompleteItems=true
check(Atr_FilterIncompleteBrowserItems(incompleteSample)==incompleteSample,'setting restores all entries unchanged including unknown categories and slots')
local sample={}
local function entry(name,class,subclass)
 sample[#sample+1]={name=name,class=class,subclass=subclass,price=100,reference=200,historyDays=4,percent=50,seen=99000,quality=1}
end
entry('Flask A','Consumable','Flask');entry('Potion A','Consumable','Potion');entry('Potion B','Consumable','Potion')
entry('Cloth Robe','Armor','Cloth');entry('Unknown Armor','Armor',nil);entry('Mystery','Unclassified',nil)
for i=1,25 do entry('Glyph '..i,'Glyph','Class '..i) end
function Atr_BuildBrowserSnapshot() return sample end
local nodes=Atr_BuildBrowserCategoryTree(sample,nil)
check(#nodes==15 and nodes[2].label=='All items' and nodes[2].count==31,'collapsed root categories and total')
nodes=Atr_BuildBrowserCategoryTree(sample,'Consumable')
check(#nodes==17 and nodes[7].subclass=='Flask' and nodes[8].subclass=='Potion' and nodes[8].count==2,'sorted expanded subcategories with correct counts')
check(#Atr_BuildBrowserCategoryTree(sample,'Favorites')==15,'special categories never expand')
check(#Atr_BuildBrowserCategoryTree({},'Consumable')==15,'empty category does not create empty branch')
Atr_ToggleOfflineBrowser()
check(Atr_OfflineBrowser:IsShown() and not AuctionFrame,'offline window works without AH loaded')
check(Atr_OfflineBrowser.backdrop.bgFile=='Interface\\DialogFrame\\UI-DialogBox-Background' or Atr_OfflineBrowser.backdrop.bgFile=='Interface\\Buttons\\WHITE8X8','dialog or flat background for offline browser')
check(Atr_BrowserCategoryScroll.count==15 and Atr_BrowserCategoryScroll.visible==19,'category scroll initialized')
check(Atr_BrowserCategoryBackground.points[1][5]==-91 and Atr_BrowserCategoryBackground.height==461,'category panel aligns with search top and details bottom')
local function category(class,subclass,slot)
 for i=1,19 do local b=_G['Atr_BrowserCategoryRow'..i];if b.node and b.node.class==class and b.node.subclass==subclass and b.node.slot==slot then return b end end
end
local b=category('Consumable');b.scripts.OnClick(b)
check(Atr_BrowserScroll.count==3 and Atr_BrowserCategoryScroll.count==17,'parent selects class and expands children')
b=category('Consumable','Potion');b.scripts.OnClick(b)
check(Atr_BrowserScroll.count==2 and b.locked,'subcategory filters rows and is highlighted')
b=category('Consumable');b.scripts.OnClick(b)
check(Atr_BrowserScroll.count==3 and Atr_BrowserCategoryScroll.count==15,'collapse returns to parent class')
b=category('Armor');b.scripts.OnClick(b)
check(category('Armor','Unknown')~=nil,'missing subclasses remain accessible under Unknown')
b=category('Glyph');b.scripts.OnClick(b)
check(Atr_BrowserCategoryScroll.count==40,'large branch creates scrollable virtual tree')
Atr_BrowserCategoryScroll.scripts.OnVerticalScroll(Atr_BrowserCategoryScroll,22*22)
check(Atr_BrowserCategoryRow1.node~=nil and Atr_BrowserCategoryRow17.node~=nil,'scroll displays later tree nodes')
-- Restore a direct-search result using All; category scroll may remain at bottom.
Atr_BrowserCategoryScroll.scripts.OnVerticalScroll(Atr_BrowserCategoryScroll,0)
b=category(nil);b.scripts.OnClick(b)
Atr_BrowserSearch:SetText('potion');Atr_BrowserSearch.scripts.OnEnterPressed(Atr_BrowserSearch)
check(Atr_BrowserScroll.count==2,'live search retained after tree navigation')
Atr_BrowserSort_price.scripts.OnClick()
check(Atr_BrowserSort_price.arrow:IsShown(),'sortable column keeps active arrow')
Atr_BrowserSearch:SetText('');Atr_BrowserSearch.scripts.OnEnterPressed(Atr_BrowserSearch)
Atr_ToggleBrowserFavorite('Flask A');Atr_RefreshOfflineBrowser()
b=category('Favorites');b.scripts.OnClick(b)
check(Atr_BrowserScroll.count==1 and b.node.count==1,'favorites category tracks current saved favorites')
local itemRow
for _,w in ipairs(widgets) do if w.data and w.data.name=='Flask A' and w.star then itemRow=w;break end end
check(itemRow~=nil,'item, favorite star and placeholder icon row retained')
itemRow.scripts.OnClick(itemRow,'LeftButton')
check(Atr_BrowserHistoryScroll.count==0,'selected item details/history render without forcing a scan')
-- Three-level equipment navigation and merged chest/robe types.
local equipment={
 {name='Hat',class='Armor',subclass='Cloth',equipLoc='INVTYPE_HEAD'},
 {name='Robe',class='Armor',subclass='Cloth',equipLoc='INVTYPE_ROBE'},
 {name='Vest',class='Armor',subclass='Cloth',equipLoc='INVTYPE_CHEST'},
 {name='Uncached',class='Armor',subclass='Cloth'},
}
local slots,counts=Atr_GetBrowserSlots(equipment,'Armor','Cloth')
check(slots[1]=='Head' and counts.Chest==2 and slots[#slots]=='Unknown slot','ordered slots, merged chest/robe, unknown metadata preserved')
check(#Atr_FilterBrowserSnapshot(equipment,'','Armor','name',false,'Cloth','Chest')==2,'slot filter matches both robe and chest')
check(#Atr_FilterBrowserSnapshot(equipment,'','Armor','name',false,'Cloth','Unknown slot')==1,'unknown slots remain available')
local leaves=Atr_BuildBrowserCategoryTree(equipment,'Armor','Cloth')
local head
for _,node in ipairs(leaves) do if node.slot=='Head' then head=node end end
check(head and head.depth==2 and head.count==1,'three-level tree emits equipment leaf with accurate count')
entry('Cloth Hood','Armor','Cloth');sample[#sample].equipLoc='INVTYPE_HEAD'
Atr_RefreshOfflineBrowser()
b=category('Armor');b.scripts.OnClick(b)
b=category('Armor','Cloth');b.scripts.OnClick(b)
b=category('Armor','Cloth','Head');check(b~=nil,'cloth expands equipment slots in the actual UI')
b.scripts.OnClick(b)
check(Atr_BrowserScroll.count==1 and b.locked,'leaf selects only head items')
b=category('Armor','Cloth');b.scripts.OnClick(b)
check(Atr_BrowserScroll.count==2,'collapsing slot branch restores all cloth items')
local striped=false
for _,w in ipairs(widgets) do
 if w.star and w.stripe and w.stripe.textureArgs and w.stripe.textureArgs[4]==.035 then striped=true end
end
check(striped,'same alternating .035 white row stripes as Deals')
check(itemRow.fields[1].textColor[1]==1 and itemRow.fields[1].textColor[2]==1,'neutral white item names match Deals')
-- Profile-based styling works before any auction house UI exists.
ElvUI={{media={backdropfadecolor={.12,.13,.14,.75}}}}
local style=widget();Atr_StyleOfflineBrowser(style,false)
check(style.backdropColor[1]==.12 and style.backdropColor[4]==.75,'ElvUI profile background used even without AH')
AuctionFrame={backdrop={GetBackdrop=function() return {bgFile='log-shell'} end,GetBackdropColor=function() return .2,.2,.2,.8 end}}
AuctionFrameBrowse={RightBackground={GetBackdrop=function() return {bgFile='log-list'} end,GetBackdropColor=function() return .1,.1,.1,.7 end}}
Atr_StyleOfflineBrowser(style,false);check(style.backdrop.bgFile=='log-shell','outer frame copies Logs shell')
Atr_StyleOfflineBrowser(style,true);check(style.backdrop.bgFile=='log-list' and style.backdropColor[4]==.7,'list frame copies Logs list colors and alpha')
local choice=Atr_BrowserTransparentBackground
choice:SetChecked(false);choice.scripts.OnClick(choice)
check(AUCTIONATOR_BROWSER_SETTINGS.browserTransparent==false,'browser opacity choice saved')
for _,surface in ipairs({Atr_OfflineBrowser,Atr_BrowserCategoryBackground,Atr_BrowserResultsBackground}) do
 check(surface.backdropColor[4]==1,'unchecked browser backgrounds are opaque')
end
choice:SetChecked(true);choice.scripts.OnClick(choice)
check(Atr_OfflineBrowser.backdropColor[4]==.8 and Atr_BrowserResultsBackground.backdropColor[4]==.8,'checked browser backgrounds share readable transparency')
Atr_OfflineBrowser:Hide();Atr_OfflineBrowser:Show()
check(choice:GetChecked() and Atr_OfflineBrowser.backdropColor[4]==.8,'browser preference survives reopening')
ElvUI=nil;AuctionFrame=nil;AuctionFrameBrowse=nil
Atr_ToggleOfflineBrowser();check(not Atr_OfflineBrowser:IsShown(),'close/toggle still hides window')
for _,spec in ipairs({{Atr_BrowserScroll,Atr_BrowserResultsBackground},{Atr_BrowserCategoryScroll,Atr_BrowserCategoryBackground},{Atr_BrowserHistoryScroll,Atr_BrowserHistoryBounds}}) do
 local bar=_G[spec[1]:GetName()..'ScrollBar']
 check(bar.points[1][2]==spec[2] and bar.points[1][3]=='TOPRIGHT' and bar.points[1][4]==3,'browser scrollbar outside each content area')
 check(bar.width==18 and bar.points[1][5]==-19 and bar.points[2][5]==19,'browser scrollbar aligns arrows to area height')
end
check(Atr_BrowserResultsBackground.width==749 and Atr_BrowserCategoryBackground.width==154,'both browser lists reserve separate scrollbar gutters')
local closeButton
for _,w in ipairs(widgets) do if w.parent==Atr_OfflineBrowser and w.text=='Close' then closeButton=w end end
check(Atr_OfflineBrowser.height==600 and closeButton.points[1][5]==-566,'footer has extra room above and below Close')
local tipLines={}
function GameTooltip:AddLine(text) tipLines[#tipLines+1]=text end
itemRow.data.link='item:1';itemRow.data.historyDays=4
function GameTooltip:SetHyperlink()
 self:AddLine('Auctionator');self:AddLine('Lowest / item: 100');self:AddLine('Updated: normal pricing')
 hooks.Atr_STWP_AddAuctionInfo(self,nil,nil,100)
end
itemRow.scripts.OnEnter(itemRow)
check(#tipLines==3,'normal tooltip price and update group is not duplicated')
tipLines={}
function GameTooltip:SetHyperlink() self:AddLine('Item name') end
itemRow.scripts.OnEnter(itemRow)
check(#tipLines==3 and tipLines[2]:find('Saved lowest / item',1,true) and tipLines[3]:find('Updated:',1,true),'saved prices remain visible if normal tooltip pricing is disabled')
tipLines={};itemRow.data.link=nil;itemRow.scripts.OnEnter(itemRow)
check(#tipLines==3 and tipLines[3]:find('Updated:',1,true),'uncached items still get one saved update line')
print('PASS: '..checks..' offline browser layout, expandable category tree, filters, scrolling, favorites and details checks')

-- A recipe/cache addon rebuilds the visible tip after the first hover.
tipLines={}
GameTooltip.scripts.OnTooltipCleared(GameTooltip)
function GameTooltip:GetOwner() return itemRow end
itemRow.scripts.OnUpdate(itemRow)
check(#tipLines==2 and tipLines[1]:find('Saved lowest / item',1,true),'first-hover tooltip rebuild restores the saved price')
itemRow.scripts.OnUpdate(itemRow)
check(#tipLines==2,'restored pricing is not appended on every frame')
print('PASS: first-hover tooltip rebuild and duplicate protection')
