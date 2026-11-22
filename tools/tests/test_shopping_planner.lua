dofile("AuctionatorRemastered/Remastered/Core/Bootstrap.lua")
dofile("AuctionatorRemastered/Remastered/Integration/LegacyBridge.lua")
-- Run from the repository root: lua5.1 tools/tests/test_shopping_planner.lua
local checks = 0
local function check(value, message)
	checks = checks + 1
	assert(value, message)
end
local frames = {}
local function widget(name, parent)
	local f = {
		name = name,
		parent = parent,
		scripts = {},
		events = {},
		shown = true,
		enabled = true,
		focused = false,
		width = 0,
		height = 0,
		offset = 0,
	}
	function f:GetName()
		return self.name
	end
	function f:SetScript(event, fn)
		self.scripts[event] = fn
	end
	function f:RegisterEvent(event)
		self.events[event] = true
	end
	function f:SetSize(w, h)
		self.width = w
		self.height = h
	end
	function f:GetWidth()
		return self.width
	end
	function f:GetHeight()
		return self.height
	end
	function f:SetPoint(...)
		self.point = { ... }
	end
	function f:ClearAllPoints()
		self.point = nil
	end
	function f:SetWidth(value)
		self.width = value
	end
	function f:GetFrameLevel()
		return self.level or 50
	end
	function f:SetBackdrop(value)
		self.backdrop = value
	end
	function f:SetBackdropColor(...)
		self.backdropColor = { ... }
	end
	function f:GetBackdropColor()
		return unpack(self.backdropColor)
	end
	function f:SetTexture(value)
		self.texture = value
	end
	function f:SetText(value)
		self.text = value
	end
	function f:GetText()
		return self.text or ""
	end
	function f:Show()
		local old = self.shown
		self.shown = true
		if not old and self.scripts.OnShow then
			self.scripts.OnShow(self)
		end
	end
	function f:Hide()
		local old = self.shown
		self.shown = false
		if old and self.scripts.OnHide then
			self.scripts.OnHide(self)
		end
	end
	function f:IsShown()
		return self.shown
	end
	function f:Enable()
		self.enabled = true
	end
	function f:Disable()
		self.enabled = false
	end
	function f:SetChecked(value)
		self.checked = value
	end
	function f:GetChecked()
		return self.checked
	end
	function f:HasFocus()
		return self.focused
	end
	function f:SetFocus()
		self.focused = true
		if self.scripts.OnEditFocusGained then
			self.scripts.OnEditFocusGained(self)
		end
	end
	function f:ClearFocus()
		local old = self.focused
		self.focused = false
		if old and self.scripts.OnEditFocusLost then
			self.scripts.OnEditFocusLost(self)
		end
	end
	function f:CreateTexture()
		return widget(nil, self)
	end
	function f:CreateFontString()
		return widget(nil, self)
	end
	setmetatable(f, {
		__index = function(_, key)
			if
				key:find("^Set")
				or key == "EnableMouse"
				or key == "RegisterForDrag"
				or key == "LockHighlight"
				or key == "UnlockHighlight"
				or key == "StopMovingOrSizing"
				or key == "StartMoving"
			then
				return function() end
			end
		end,
	})
	frames[#frames + 1] = f
	if name then
		_G[name] = f
	end
	return f
end
function CreateFrame(_, name, parent, template)
	local f = widget(name, parent)
	if template == "FauxScrollFrameTemplate" then
		f.ScrollBar = widget(name .. "ScrollBar", f)
		widget(name .. "ScrollBarScrollUpButton", f.ScrollBar)
		widget(name .. "ScrollBarScrollDownButton", f.ScrollBar)
	end
	return f
end
function hooksecurefunc() end
function CloseDropDownMenus() end
function StaticPopup_Show() end
function StaticPopup_Hide() end
function FauxScrollFrame_SetOffset(f, value)
	f.offset = value
end
function FauxScrollFrame_GetOffset(f)
	return f.offset
end
function FauxScrollFrame_Update() end
function FauxScrollFrame_OnVerticalScroll(f, value, height, fn)
	f.offset = math.floor(value / height)
	fn()
end
function IsMouseButtonDown()
	return false
end
function MouseIsOver()
	return false
end
local character = "Main"
function UnitName()
	return character
end
function GetRealmName()
	return "Realm"
end
function UnitFactionGroup()
	return "Alliance"
end
function time()
	return 123456
end
function date()
	return "test date"
end
UIParent = widget()
UIParent:SetSize(1600, 1000)
StaticPopupDialogs = {}
UISpecialFrames = {}
ACCEPT = "Accept"
CANCEL = "Cancel"
YES = "Yes"
NO = "No"
gAtrZC = { priceToMoneyString = tostring }
GameTooltip = { SetOwner = function() end, AddLine = function() end, Show = function() end, Hide = function() end }
function Atr_MarketPercentText()
	return "100%*"
end
local containers = {}
function GetContainerNumSlots(bag)
	return #(containers[bag] or {})
end
function GetContainerItemLink(bag, slot)
	local item = containers[bag][slot]
	return "|Hitem:1|h[" .. item[1] .. "]|h"
end
function GetContainerItemInfo(bag, slot)
	return "icon", containers[bag][slot][2]
end
local known = { Cloth = true, Herb = true, Dust = true, ["Blade of Strength"] = true, ["Blade of Stamina"] = true }
function GetItemInfo(query)
	local name = query:match("|h%[(.-)%]|h") or query
	if known[name] then
		return name, "|Hitem:1|h[" .. name .. "]|h", 2, nil, nil, nil, nil, nil, nil, "Icon:" .. name
	end
end
function Atr_BuildBrowserSnapshot()
	return { { name = "Cloth", price = 100, texture = "ClothIcon", historyDays = 1 }, {
		name = "Herb",
		price = 20,
		historyDays = 1,
	} }
end
-- Exercise the existing shopping-list implementation, not a duplicate of it.
local file = assert(io.open("AuctionatorRemastered/Legacy/AuctionatorShop.lua"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
Atr_SList = {}
Atr_SList.__index = Atr_SList
ATR_MAXNUM_ITEMS_ON_SHOPPING_LIST = 50
local definitions = {}
for _, name in ipairs({
	"Atr_SList.create",
	"Atr_SortSlists",
	"Atr_SList.FindByName",
	"Atr_SList:AddItem",
	"Atr_SList:FindItemIndex",
}) do
	definitions[#definitions + 1] = assert(source:match("(function " .. name:gsub("%.", "%%.") .. " %b().-\nend)"))
end
assert(loadstring("local zc=...;local gTempShoppingList; " .. table.concat(definitions, "\n")))({
	StringSame = function(a, b)
		return a:lower() == b:lower()
	end,
})
file = assert(io.open("AuctionatorRemastered/Remastered/Data/BrowserData.lua"))
local browser = file:read("*a")
file:close()
assert(loadstring(browser:sub(1, browser:find("local db=", 1, true) - 1)))()
dofile("AuctionatorRemastered/Remastered/UI/Theme.lua")

AUCTIONATOR_SHOPPING_LISTS = {}
local recent = Atr_SList.create("Recent Searches", true)
local list = Atr_SList.create("Supplies")
list:AddItem("Cloth")
list:AddItem("Herb")
list:AddItem("Dust")
list:AddItem("flask/*")
assert(loadfile("AuctionatorRemastered/Remastered/Features/ShoppingPlanner.lua"))()
check(Atr_GetShoppingTarget(list, "Cloth") == 0, "unset targets default to zero without changing items")
check(Atr_SetShoppingTarget(list, "Cloth", 20), "target saved")
check(Atr_SetShoppingTarget(list, "Herb", 100), "second target")
check(Atr_SetShoppingTarget(list, "Dust", 1), "explicit target for missing-price coverage")
check(not Atr_SetShoppingTarget(list, "Cloth", -1), "negative target rejected")
check(not Atr_SetShoppingTarget(list, "Cloth", 1.5), "fractional target rejected")
check(not Atr_SetShoppingTarget(list, "Cloth", ""), "empty target rejected")
check(not Atr_SetShoppingTarget(list, "Cloth", 100000), "target cap")
check(not Atr_SetShoppingTarget(recent, "Cloth", 20), "recent searches cannot receive targets")
check(not Atr_SetShoppingTarget(list, "Missing", 20), "stale entry cannot receive target")
local catalog = { Cloth = { known = true, price = 100 }, Herb = { known = true, price = 20 }, Dust = { known = true } }
local plan = Atr_BuildShoppingPlan(list, catalog, { Cloth = 7, Herb = 40 }, { Cloth = 3, Herb = 10 }, true)
check(
	plan.need == 61 and plan.total == 2000 and plan.unpriced == 1 and plan.unknown == 1,
	"partial estimate includes only known missing item costs"
)
check(
	plan.rows[1].name == "Cloth" and plan.rows[1].owned == 10 and plan.rows[1].need == 10 and plan.rows[1].cost == 1000,
	"want is total owned target"
)
local bagsOnly = Atr_BuildShoppingPlan(list, catalog, { Cloth = 7, Herb = 40 }, nil, false)
check(bagsOnly.need == 74 and bagsOnly.total == 2500, "bags-only arithmetic")
check(Atr_SetShoppingTarget(list, "Dust", 0), "zero target supported")
plan = Atr_BuildShoppingPlan(list, catalog, { Cloth = 25, Herb = 100 }, nil, false)
check(
	plan.need == 0 and plan.total == 0 and plan.ready == 3 and plan.unpriced == 0,
	"no negative need; fulfilled unknown-price item costs zero"
)
check(type(list.items[1]) == "string" and list.remasteredTargets.Cloth == 20, "native Buy list structure unchanged")
check(
	Atr_BrowserRenameShoppingList(list, "Renamed") and list.remasteredTargets.Cloth == 20,
	"list rename preserves targets"
)
check(
	Atr_BrowserEditShoppingItem(list, "Dust", "Dust renamed") and list.remasteredTargets["Dust renamed"] == 0,
	"entry rename moves target"
)
check(
	Atr_BrowserRemoveShoppingItem(list, "Dust renamed") and list.remasteredTargets["Dust renamed"] == nil,
	"entry removal removes target"
)
-- Real bag names keep random-suffix items separate, even with the same item ID.
containers[0] = { { "Cloth", 7 }, { "Herb", 4 }, { "Blade of Strength", 3 }, { "Blade of Stamina", 2 } }
local counts = Atr_GetShoppingBagCounts()
check(counts["Blade of Strength"] == 3 and counts["Blade of Stamina"] == 2, "variant names counted separately")
Atr_ShowBrowserShoppingLists(list)
check(Atr_BrowserShoppingLists:IsShown(), "planner opens without AH")
check(Atr_BrowserShoppingLists.width == 1100 and Atr_BrowserShoppingLists.height == 570, "planner geometry")
local function findItem(name)
	for _, frame in ipairs(frames) do
		if frame.itemName == name and frame.want then
			return frame
		end
	end
end
local cloth = findItem("Cloth")
check(
	cloth and cloth.need:GetText() == "13" and cloth.cost:GetText() == "1300",
	"before bank visit uses known bags only"
)
check(cloth.icon.texture == "ClothIcon", "item icons retained")
check(
	Atr_BrowserShoppingLists.backdrop.edgeSize == 2 and Atr_ShoppingResultsBackground.backdrop.edgeSize == 2,
	"shared browser shell and result theme"
)
check(Atr_ShoppingResultsBackground.width == 831 and cloth.width == 823, "rows remain inset within the result border")
check(
	Atr_BrowserShoppingItemScroll.ScrollBar.width == 18
		and Atr_BrowserShoppingItemScroll.ScrollBar.point[2] == Atr_ShoppingResultsBackground,
	"result scrollbar uses its own outer gutter"
)
check(
	Atr_BrowserShoppingListScroll.ScrollBar.point[2] == Atr_ShoppingListBounds,
	"list selector scrollbar stays within its management group"
)
check(cloth.want:GetName() == "Atr_ShoppingWant1", "named quantity inputs support ElvUI texture skinning")
check(not findItem("flask/*").want.planEnabled, "search terms cannot be planned as exact items")
local events
for _, frame in ipairs(frames) do
	if frame.events.BANKFRAME_OPENED then
		events = frame
	end
end
check(events ~= nil, "inventory observer registered")
containers[-1] = { { "Cloth", 3 } }
containers[5] = { { "Herb", 6 } }
events.scripts.OnEvent(events, "BANKFRAME_OPENED")
check(cloth.owned:GetText() == "10" and cloth.need:GetText() == "10", "bank snapshot included")
containers[0][1][2] = 9
containers[-1][1][2] = 1
events.scripts.OnEvent(events, "BAG_UPDATE")
events.scripts.OnUpdate(events, 0.25)
check(cloth.owned:GetText() == "10", "moving bank items to bags does not change total ownership")
events.scripts.OnEvent(events, "BANKFRAME_CLOSED")
containers[-1] = {}
containers[5] = {}
events.scripts.OnEvent(events, "BAG_UPDATE")
events.scripts.OnUpdate(events, 0.25)
check(cloth.owned:GetText() == "10", "closing bank retains last recorded contents")
Atr_ShoppingIncludeBank:SetChecked(false)
Atr_ShoppingIncludeBank.scripts.OnClick(Atr_ShoppingIncludeBank)
check(cloth.owned:GetText() == "9" and cloth.need:GetText() == "11", "include-bank checkbox")
cloth.want:SetFocus()
cloth.want:SetText("25")
cloth.want.scripts.OnEnterPressed(cloth.want)
check(list.remasteredTargets.Cloth == 25 and cloth.need:GetText() == "16", "quantity input saves and recalculates")
cloth.want:SetFocus()
cloth.want:SetText("26")
cloth.want.scripts.OnEscapePressed(cloth.want)
check(list.remasteredTargets.Cloth == 25 and cloth.want:GetText() == "25", "Escape discards quantity edit")
cloth.want:SetFocus()
cloth.want:SetText("")
cloth.want:ClearFocus()
check(list.remasteredTargets.Cloth == 25 and cloth.want:GetText() == "25", "invalid edit restores previous target")
cloth.want:SetFocus()
cloth.want:SetText("30")
Atr_ShoppingIncludeBank:SetChecked(true)
Atr_ShoppingIncludeBank.scripts.OnClick(Atr_ShoppingIncludeBank)
check(
	list.remasteredTargets.Cloth == 30 and AUCTIONATOR_BROWSER_SETTINGS.shoppingIncludeBank == true,
	"checkbox change survives quantity focus-loss redraw"
)
character = "Alt"
Atr_ShoppingIncludeBank:SetChecked(true)
Atr_ShoppingIncludeBank.scripts.OnClick(Atr_ShoppingIncludeBank)
check(cloth.owned:GetText() == "9", "bank cache isolated by character")
character = "Main"
check(
	AUCTIONATOR_BROWSER_SETTINGS.shoppingBanks["Realm/Main"].counts.Cloth == 1,
	"bank persists in existing saved settings"
)
assert(loadfile("AuctionatorRemastered/Remastered/Features/ShoppingPlanner.lua"))()
Atr_ShowBrowserShoppingLists(list)
local afterReload = findItem("Cloth")
-- Locate the new module's row rather than the previous mock window.
for _, f in ipairs(frames) do
	if f.itemName == "Cloth" and f.want then
		afterReload = f
	end
end
check(
	afterReload.want:GetText() == "30" and afterReload.owned:GetText() == "10",
	"targets and bank counts survive a module reload"
)
check(QueryAuctionItems == nil and AuctionFrame == nil, "planner needs no AH queries or frame")
ElvUI = { { media = { backdropfadecolor = { 0.12, 0.13, 0.14, 0.4 } } } }
Atr_BrowserShoppingLists:Hide()
Atr_BrowserShoppingLists:Show()
for _, surface in ipairs({ Atr_BrowserShoppingLists, Atr_ShoppingListsBackground, Atr_ShoppingResultsBackground }) do
	check(
		surface.backdropColor[1] == 0.12 and surface.backdropColor[4] == 1,
		"planner preserves ElvUI colors but overrides transparency on reopen"
	)
end
check(Atr_ShoppingListsBackground.height == 473, "list panel bottom aligns with Remove entry footer")
local choice = Atr_ShoppingTransparentBackground
check(not choice:GetChecked(), "planner defaults to opaque")
AUCTIONATOR_BROWSER_SETTINGS.browserTransparent = false
choice:SetChecked(true)
choice.scripts.OnClick(choice)
for _, surface in ipairs({ Atr_BrowserShoppingLists, Atr_ShoppingListsBackground, Atr_ShoppingResultsBackground }) do
	check(surface.backdropColor[4] == 0.8, "planner checkbox updates every background immediately")
end
check(
	AUCTIONATOR_BROWSER_SETTINGS.shoppingTransparent and AUCTIONATOR_BROWSER_SETTINGS.browserTransparent == false,
	"planner choice is independent of browser preference"
)
Atr_BrowserShoppingLists:Hide()
Atr_BrowserShoppingLists:Show()
check(choice:GetChecked() and Atr_BrowserShoppingLists.backdropColor[4] == 0.8, "planner preference survives reopening")
choice:SetChecked(false)
choice.scripts.OnClick(choice)
check(Atr_BrowserShoppingLists.backdropColor[4] == 1, "planner can return to opaque")
check(choice.point[4] == 24 and choice.point[5] == -10, "checkbox uses matching top-left placement")
ElvUI = nil

-- =========================================================================
-- Crafting Shopping List Test
-- =========================================================================
function GetTradeSkillSelectionIndex()
	return 1
end
function GetTradeSkillInfo(idx)
	if idx == 1 then
		return "Heavy Frostweave Bandage"
	end
end
function GetTradeSkillNumReagents(idx)
	if idx == 1 then
		return 1
	end
	return 0
end
function GetTradeSkillReagentInfo(idx, rIdx)
	if idx == 1 and rIdx == 1 then
		return "Frostweave Cloth", "Interface\\Icons\\INV_Fabric_Frostweave_Bolt", 2
	end
end

local ok, msg = Atr_CreateCraftingShoppingList(1)
check(ok == true, "Atr_CreateCraftingShoppingList should succeed")
local craftList = Atr_SList.FindByName("Craft: Heavy Frostweave Bandage", { skipTempList = true })
check(craftList ~= nil, "Crafting shopping list should be created")
check(craftList.items[1] == "Frostweave Cloth", "Reagent should be on shopping list")
check(craftList.remasteredTargets["Frostweave Cloth"] ~= nil, "Target quantity should be set")

print("PASS: " .. checks .. " shopping-plan, inventory, bank-cache and UI checks")
