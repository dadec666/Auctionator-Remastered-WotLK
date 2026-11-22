-- Standalone browser view; saved data and item classification live in Data/BrowserData.lua.
local Browser = AuctionatorRemastered.Browser
local settings, db = Browser.Settings, Browser.Database
local function shoppingNotice(ok, message)
	if UIErrorsFrame then
		UIErrorsFrame:AddMessage(message, ok and 0.3 or 1, ok and 1 or 0.3, 0.3, 1)
	end
end

-- SetHyperlink may already append Auctionator's normal price group through
-- tooltip hooks. Detect that render rather than appending the same data twice.
local tooltipHasPrice = false
GameTooltip:HookScript("OnTooltipCleared", function()
	tooltipHasPrice = false
end)
AuctionatorRemastered.Legacy.Hook("Atr_STWP_AddAuctionInfo", function(tip, _, _, price)
	if tip == GameTooltip and type(price) == "number" and price > 0 then
		tooltipHasPrice = true
	end
end)

local window, search, scroll, info, countText, detailName, detailInfo, icon, historyScroll, detailFrame
local snapshot, results, rows, categoryButtons, historyRows = {}, {}, {}, {}, {}
local selected, selectedClass, sortKey, descending, history = nil, nil, "name", false, {}
local searchLinkTarget = false
local selectedSubclass, selectedSlot, categoryScroll, expandedClass, expandedSubclass
local categoryNodes, headerButtons = {}, {}
local shoppingMenu, shoppingItem
local refreshButton, metadataStatus, chartButton
local function insertChatLink(entry)
	-- Only exact known links are safe for random-suffix items.
	if entry and entry.link and IsShiftKeyDown() and Atr_InsertChatLink then
		return Atr_InsertChatLink(entry.link)
	end
end
local function money(value)
	return value and gAtrZC.priceToMoneyString(math.floor(value + 0.5)) or "--"
end
local function age(timestamp)
	if not timestamp then
		return "Unknown"
	end
	local seconds = math.max(0, time() - timestamp)
	if seconds < 60 then
		return "Just now"
	end
	if seconds < 3600 then
		return math.floor(seconds / 60) .. " min ago"
	end
	if seconds < 86400 then
		return math.floor(seconds / 3600) .. " hr ago"
	end
	return math.floor(seconds / 86400) .. " days ago"
end
local function renderHistory()
	FauxScrollFrame_Update(historyScroll, #history, 4, 18)
	local offset = FauxScrollFrame_GetOffset(historyScroll)
	for i, row in ipairs(historyRows) do
		local data = history[offset + i]
		row:SetText(
			data and (date("%Y-%m-%d", gScanHistDayZero + data.day * 86400) .. "     " .. money(data.low)) or ""
		)
	end
end
local function updateDetails()
	if not selected then
		detailName:SetText(
			ZT and ZT("Select an item to view its saved prices") or "Select an item to view its saved prices"
		)
		detailInfo:SetText("")
		icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		if chartButton then
			chartButton:Disable()
		end
		history = {}
		renderHistory()
		return
	end
	if chartButton then
		chartButton:Enable()
	end
	detailName:SetText(selected.link or selected.name)
	icon:SetTexture(selected.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
	detailInfo:SetText(
		"Lowest / item: "
			.. money(selected.price)
			.. "\n"
			.. Atr_GetMarketHistoryDays()
			.. "-day reference: "
			.. money(selected.reference)
			.. "\nUpdated: "
			.. age(selected.seen)
			.. "\n"
			.. (
				selected.historyDays > 0
					and (selected.historyDays < 3 and "Preliminary: " or "") .. selected.historyDays .. " history days"
				or "Preliminary: latest saved low"
			)
	)
	if selected.identityPending then
		detailInfo:SetText(detailInfo:GetText() .. "\nItem identity pending; scan again to confirm.")
	end
	history = Atr_GetBrowserHistory(selected.itemKey or selected.name)
	FauxScrollFrame_SetOffset(historyScroll, 0)
	historyScroll:SetVerticalScroll(0)
	renderHistory()
end
local function render()
	FauxScrollFrame_Update(scroll, #results, 10, 25)
	local offset = FauxScrollFrame_GetOffset(scroll)
	for i, row in ipairs(rows) do
		local data = results[offset + i]
		row.data = data
		if data then
			local favorite = Atr_IsBrowserFavorite(data.itemKey or data.name)
			row.star.texture:SetVertexColor(favorite and 1 or 0.5, favorite and 0.85 or 0.5, favorite and 0.2 or 0.5)
			row.star.texture:SetAlpha(favorite and 1 or 0.45)
			row.icon:SetTexture(data.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
			row.fields[1]:SetText(data.name)
			row.fields[1]:SetTextColor(1, 1, 1)
			row.fields[2]:SetText(money(data.price))
			row.fields[3]:SetText(money(data.reference))
			row.fields[4]:SetText(Atr_MarketPercentText(data.itemKey or data.name, data.price, 1, db()))
			row.fields[5]:SetText(age(data.seen))
			if selected and (selected.itemKey or selected.name) == (data.itemKey or data.name) then
				row:LockHighlight()
			else
				row:UnlockHighlight()
			end
			row:Show()
		else
			row:Hide()
		end
	end
	local unclassified = 0
	for _, item in ipairs(snapshot) do
		if item.class == "Unclassified" then
			unclassified = unclassified + 1
		end
	end
	countText:SetText(
		string.format(ZT and ZT("%d matches / %d saved items") or "%d matches / %d saved items", #results, #snapshot)
			.. (
				unclassified > 0
					and ("  -  " .. unclassified .. " " .. (ZT and ZT("unclassified (included in All items)") or "unclassified (included in All items)"))
				or ""
			)
	)
end
local function renderCategories()
	if not categoryScroll then
		return
	end
	categoryNodes = Atr_BuildBrowserCategoryTree(snapshot, expandedClass, expandedSubclass)
	FauxScrollFrame_Update(categoryScroll, #categoryNodes, 19, 22)
	local offset = math.min(FauxScrollFrame_GetOffset(categoryScroll), math.max(0, #categoryNodes - 19))
	FauxScrollFrame_SetOffset(categoryScroll, offset)
	for i, button in ipairs(categoryButtons) do
		local node = categoryNodes[offset + i]
		button.node = node
		if node then
			local prefix = node.expandable and (node.open and "- " or "+ ") or ""
			local displayLabel = ZT and ZT(node.label) or node.label
			button:SetText(prefix .. displayLabel .. " (" .. node.count .. ")")
			button:SetNormalFontObject(node.depth > 0 and GameFontHighlightSmall or GameFontNormalSmall)
			-- SetText creates the font string lazily; font changes can also
			-- restore its default centering. Apply alignment after both.
			local font = button:GetFontString()
			if font then
				local inset = 3 + node.depth * 10
				font:ClearAllPoints()
				font:SetPoint("LEFT", button, "LEFT", inset, 0)
				font:SetWidth(142 - inset)
				font:SetHeight(20)
				font:SetJustifyH("LEFT")
			end
			if node.class == selectedClass and node.subclass == selectedSubclass and node.slot == selectedSlot then
				button:LockHighlight()
			else
				button:UnlockHighlight()
			end
			button:Show()
		else
			button:Hide()
		end
	end
end
local function applyFilters(preserveScroll)
	local offset = preserveScroll and FauxScrollFrame_GetOffset(scroll) or 0
	if not selectedClass or selectedClass == "Favorites" or selectedClass == "Unclassified" then
		selectedSubclass = nil
		selectedSlot = nil
	elseif selectedSubclass then
		local _, counts = Atr_GetBrowserSubcategories(snapshot, selectedClass)
		if not counts[selectedSubclass] then
			selectedSubclass = nil
			selectedSlot = nil
		end
	end
	results = Atr_FilterBrowserSnapshot(
		snapshot,
		search:GetText(),
		selectedClass,
		sortKey,
		descending,
		selectedSubclass,
		selectedSlot
	)
	offset = math.min(offset, math.max(0, #results - 10))
	FauxScrollFrame_SetOffset(scroll, offset)
	scroll:SetVerticalScroll(offset * 25)
	for key, button in pairs(headerButtons) do
		if key == sortKey then
			button.arrow:SetTexCoord(0, 1, descending and 0 or 1, descending and 1 or 0)
			button.arrow:Show()
		else
			button.arrow:Hide()
		end
	end
	renderCategories()
	render()
end
local function rebuild()
	snapshot = Atr_FilterIncompleteBrowserItems(Atr_BuildBrowserSnapshot())
	if selectedClass == "Unclassified" and not settings().showIncompleteItems then
		selectedClass = nil
		selectedSubclass = nil
		selectedSlot = nil
	end
	if selected then
		local name = selected.itemKey or selected.name
		selected = nil
		for _, entry in ipairs(snapshot) do
			if (entry.itemKey or entry.name) == name then
				selected = entry
				break
			end
		end
	end
	info:SetText("Saved scan data - " .. GetRealmName() .. " / " .. UnitFactionGroup("player"))
	refreshButton:SetText("Refresh data")
	applyFilters()
	updateDetails()
end
-- Route modified item clicks only to a visible, focused browser search.
-- Replace the query with a plain name, never a colored hyperlink string.
function Atr_InsertBrowserSearchLink(link)
	if not IsShiftKeyDown() then
		return false
	end
	local target, offline
	if window and window:IsShown() and search then
		target = search
		offline = true
	elseif Atr_DealsPanel and Atr_DealsPanel:IsShown() then
		target = Atr_DealsSearch
	elseif Atr_TradingLogs and Atr_TradingLogs:IsShown() then
		target = Atr_LogsSearch
	end
	if not target then
		return false
	end
	local focus = GetCurrentKeyboardFocus and GetCurrentKeyboardFocus()
	-- Keep intentional chat and other edit-box input working normally.
	if focus and focus ~= target then
		return false
	end
	if type(link) ~= "string" then
		return false
	end
	local kind, id = link:match("|H(%a+):(%d+)")
	if not kind then
		kind, id = link:match("^(%a+):(%d+)")
	end
	if kind ~= "item" and kind ~= "spell" and kind ~= "enchant" then
		return false
	end
	local name
	if kind == "item" then
		name = GetItemInfo(link)
	elseif GetSpellInfo then
		name = GetSpellInfo(tonumber(id))
	end
	name = name or link:match("|h%[(.-)%]|h")
	if not name or name == "" then
		return false
	end
	if offline then
		selectedClass = nil
		selectedSubclass = nil
		selectedSlot = nil
	end
	target:SetText(name)
	target:HighlightText()
	if offline then
		applyFilters()
	end
	return true
end
-- These hooks must exist BEFORE Blizzard_AuctionUI is loaded. Auctionator's
-- original hooks are installed only when visiting AH and are not enough offline.
local browserLinkHooks = {}
function Atr_InstallBrowserLinkHooks()
	for _, name in ipairs({ "ChatEdit_InsertLink", "HandleModifiedItemClick", "ContainerFrameItemButton_OnModifiedClick" }) do
		if not browserLinkHooks[name] and type(_G[name]) == "function" then
			local original = _G[name]
			if name == "ContainerFrameItemButton_OnModifiedClick" then
				_G[name] = function(slot, button, ...)
					if button == "LeftButton" and IsShiftKeyDown() and slot and slot.GetParent and slot.GetID then
						local parent = slot:GetParent()
						local link = parent and parent.GetID and GetContainerItemLink(parent:GetID(), slot:GetID())
						if Atr_InsertBrowserSearchLink(link) then
							return true
						end
					end
					return original(slot, button, ...)
				end
			else
				_G[name] = function(link, ...)
					if Atr_InsertBrowserSearchLink(link) then
						return true
					end
					return original(link, ...)
				end
			end
			browserLinkHooks[name] = true
		end
	end
end
Atr_InstallBrowserLinkHooks()
local skilletLinkHooked = false
local function hookSkilletLinks()
	if not skilletLinkHooked and Skillet and type(Skillet.SetSelectedSkill) == "function" then
		hooksecurefunc(Skillet, "SetSelectedSkill", function(self, index, clicked)
			if clicked and index and index > 0 and GetTradeSkillItemLink then
				Atr_InsertBrowserSearchLink(GetTradeSkillItemLink(index))
			end
		end)
		skilletLinkHooked = true
	end
end
local linkEvents = CreateFrame("Frame")
linkEvents:RegisterEvent("ADDON_LOADED")
linkEvents:RegisterEvent("TRADE_SKILL_SHOW")
linkEvents:SetScript("OnEvent", function()
	Atr_InstallBrowserLinkHooks()
	hookSkilletLinks()
end)
hookSkilletLinks()

local function styleBrowserSurface(surface, body)
	Atr_StyleOfflineBrowser(surface, body, settings().browserTransparent ~= false)
end

local function createWindow()
	window = CreateFrame("Frame", "Atr_OfflineBrowser", UIParent)
	window:SetSize(980, 600)
	window:SetPoint("CENTER")
	window:SetFrameStrata("DIALOG")
	window:SetClampedToScreen(true)
	window:EnableMouse(true)
	window:SetMovable(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", function(self)
		if search then
			search:ClearFocus()
		end
		self:StartMoving()
	end)
	window:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
	end)
	if UISpecialFrames then
		table.insert(UISpecialFrames, "Atr_OfflineBrowser")
	end
	styleBrowserSurface(window, false)
	local function backdrop(name, x, y, width, height)
		local frame = CreateFrame("Frame", name, window)
		frame:SetPoint("TOPLEFT", window, "TOPLEFT", x, y)
		frame:SetSize(width, height)
		frame:SetFrameLevel(window:GetFrameLevel())
		styleBrowserSurface(frame, true)
		return frame
	end
	backdrop("Atr_BrowserCategoryBackground", 14, -91, 154, 461)
	backdrop("Atr_BrowserResultsBackground", 200, -155, 749, 255)
	local function text(parent, value, x, y, template)
		local font = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
		font:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
		font:SetText(value)
		font:SetJustifyH("LEFT")
		return font
	end
	local function button(parent, label, x, y, width, callback)
		local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
		Atr_AnalysisSkin(b, "Button")
		b:SetSize(width, 22)
		b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
		b:SetText(label)
		b:SetScript("OnClick", function(...)
			if search then
				search:ClearFocus()
			end
			callback(...)
		end)
		return b
	end
	local title = text(
		window,
		ZT and ZT("Auctionator Remastered - Browser") or "Auctionator Remastered - Browser",
		0,
		0,
		"GameFontNormal"
	)
	title:ClearAllPoints()
	title:SetPoint("TOP", window, "TOP", 0, -12)
	local updateBackgrounds
	local backgroundChoice = Atr_CreateBackgroundCheckbox(
		window,
		"Atr_BrowserTransparentBackground",
		settings().browserTransparent ~= false,
		function(checked)
			settings().browserTransparent = checked
			updateBackgrounds()
		end
	)
	info = text(window, ZT and ZT("Saved scan data") or "Saved scan data", 24, -44)
	button(window, ZT and ZT("Shopping lists") or "Shopping lists", 805, -40, 145, function()
		Atr_ShowBrowserShoppingLists()
	end)
	-- Separate popup: the original creator also manipulates the live AH UI.
	local function acceptShoppingList(popup)
		local ok, message = Atr_BrowserCreateShoppingList(popup.editBox:GetText(), popup.data)
		shoppingNotice(ok, message)
		return not ok
	end
	StaticPopupDialogs["ATR_BROWSER_NEW_SHOPPING_LIST"] = {
		text = ZT and ZT("Name for your new shopping list") or "Name for your new shopping list",
		button1 = ACCEPT,
		button2 = CANCEL,
		hasEditBox = 1,
		maxLetters = 32,
		timeout = 0,
		exclusive = 1,
		whileDead = 1,
		hideOnEscape = 1,
		OnShow = function(self)
			self.editBox:SetText("")
			self.editBox:SetFocus()
		end,
		OnAccept = acceptShoppingList,
		EditBoxOnEnterPressed = function(self)
			local popup = self:GetParent()
			if not acceptShoppingList(popup) then
				popup:Hide()
			end
		end,
		EditBoxOnEscapePressed = function(self)
			self:GetParent():Hide()
		end,
	}
	shoppingMenu = CreateFrame("Frame", "Atr_BrowserShoppingMenu", UIParent, "UIDropDownMenuTemplate")
	UIDropDownMenu_Initialize(shoppingMenu, function(self, level)
		if InCombatLockdown and InCombatLockdown() then
			return
		end
		level = level or 1
		if not shoppingItem then
			return
		end
		local function add(text, callback, disabled, arrow, title)
			local option = UIDropDownMenu_CreateInfo()
			option.text = text
			option.func = callback
			option.disabled = disabled
			option.notCheckable = true
			option.hasArrow = arrow
			option.isTitle = title
			UIDropDownMenu_AddButton(option, level)
		end
		if level == 1 then
			add(shoppingItem, nil, true, nil, true)
			add(ZT and ZT("Add to shopping list") or "Add to shopping list", nil, nil, true)
			add(ZT and ZT("Cancel") or "Cancel", function()
				CloseDropDownMenus()
			end)
		elseif level == 2 then
			local itemName = shoppingItem
			for _, list in ipairs(AUCTIONATOR_SHOPPING_LISTS or {}) do
				if not list.isRecents then
					local target = list
					local duplicate = Atr_SList.FindItemIndex(target, itemName) > 0
					local full = #target.items >= ATR_MAXNUM_ITEMS_ON_SHOPPING_LIST
					local suffix = duplicate and " (already added)" or (full and " (full)" or "")
					add(target.name .. suffix, function()
						CloseDropDownMenus()
						shoppingNotice(Atr_BrowserAddToShoppingList(target, itemName))
					end, duplicate or full)
				end
			end
			add(ZT and ZT("New shopping list...") or "New shopping list...", function()
				CloseDropDownMenus()
				StaticPopup_Show("ATR_BROWSER_NEW_SHOPPING_LIST", nil, nil, itemName)
			end)
		end
	end, "MENU")
	local close = CreateFrame("Button", "Atr_OfflineBrowserCloseButton", window, "UIPanelCloseButton")
	Atr_AnalysisSkin(close, "CloseButton")
	close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -6, -6)
	close:SetScript("OnClick", function()
		window:Hide()
	end)
	text(window, ZT and ZT("Name") or "Name", 208, -70, "GameFontNormal")
	search = CreateFrame("EditBox", "Atr_BrowserSearch", window, "InputBoxTemplate")
	Atr_AnalysisSkin(search, "EditBox")
	search:SetSize(390, 24)
	search:SetPoint("TOPLEFT", window, "TOPLEFT", 208, -91)
	search:SetAutoFocus(false)
	search:SetScript("OnEditFocusGained", function()
		searchLinkTarget = true
	end)
	search:SetScript("OnEditFocusLost", function()
		-- Some bag/profession UIs clear keyboard focus on mouse-down before
		-- delivering the modified click. Retain its intended target for Shift.
		if not IsShiftKeyDown() then
			searchLinkTarget = false
		end
	end)
	local pendingSearch
	search:SetScript("OnTextChanged", function()
		pendingSearch = 0.15
	end)
	search:SetScript("OnEnterPressed", function(self)
		pendingSearch = nil
		applyFilters()
		searchLinkTarget = false
		self:ClearFocus()
	end)
	search:SetScript("OnEscapePressed", function(self)
		searchLinkTarget = false
		self:ClearFocus()
	end)
	search:SetScript("OnUpdate", function(self, elapsed)
		if pendingSearch then
			pendingSearch = pendingSearch - elapsed
			if pendingSearch <= 0 then
				pendingSearch = nil
				applyFilters()
			end
		end
	end)
	button(window, ZT and ZT("Search") or "Search", 612, -91, 85, function()
		applyFilters()
		search:ClearFocus()
	end)
	refreshButton = button(window, ZT and ZT("Refresh data") or "Refresh data", 710, -91, 115, rebuild)
	refreshButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(ZT and ZT("Reload saved prices") or "Reload saved prices")
		GameTooltip:AddLine(
			ZT and ZT("Refreshes this window from your local database. No AH scan is started.")
				or "Refreshes this window from your local database. No AH scan is started.",
			1,
			1,
			1,
			true
		)
		GameTooltip:Show()
	end)
	refreshButton:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	button(window, ZT and ZT("Clear search") or "Clear search", 836, -91, 115, function()
		search:SetText("")
		applyFilters()
	end)
	text(window, ZT and ZT("Categories") or "Categories", 25, -70, "GameFontNormal")
	categoryScroll = CreateFrame("ScrollFrame", "Atr_BrowserCategoryScroll", window, "FauxScrollFrameTemplate")
	categoryScroll:SetPoint("TOPLEFT", window, "TOPLEFT", 18, -95)
	categoryScroll:SetSize(146, 418)
	Atr_StyleAnalysisScroll(categoryScroll, Atr_BrowserCategoryBackground)
	categoryScroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, 22, renderCategories)
	end)
	for i = 1, 19 do
		local b = CreateFrame("Button", "Atr_BrowserCategoryRow" .. i, window)
		b:SetSize(144, 22)
		b:SetPoint("TOPLEFT", window, "TOPLEFT", 20, -95 - (i - 1) * 22)
		b:SetNormalFontObject(GameFontNormalSmall)
		b:SetHighlightFontObject(GameFontHighlightSmall)
		b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
		b:SetText("")
		local font = b:GetFontString()
		if font then
			font:ClearAllPoints()
			font:SetPoint("LEFT", b, "LEFT", 3, 0)
			font:SetWidth(139)
			font:SetHeight(20)
			font:SetJustifyH("LEFT")
		end
		b:SetScript("OnClick", function(self)
			local node = self.node
			if not node then
				return
			end
			search:ClearFocus()
			CloseDropDownMenus()
			selectedClass, selectedSubclass, selectedSlot = node.class, node.subclass, node.slot
			if node.depth == 0 then
				expandedSubclass = nil
				expandedClass = node.expandable and (expandedClass ~= node.class and node.class or nil) or nil
			elseif node.depth == 1 then
				expandedSubclass = node.expandable and (expandedSubclass ~= node.subclass and node.subclass or nil)
					or nil
			end
			applyFilters()
		end)
		categoryButtons[i] = b
	end
	local specs = {
		{ ZT and ZT("Item") or "Item", 56, 226, "name" },
		{ ZT and ZT("Lowest / item") or "Lowest / item", 285, 115, "price" },
		{ ZT and ZT("Reference") or "Reference", 410, 115, "reference" },
		{ ZT and ZT("Market %") or "Market %", 535, 80, "percent" },
		{ ZT and ZT("Updated") or "Updated", 625, 110, "seen" },
	}
	for _, spec in ipairs(specs) do
		local key = spec[4]
		local header = CreateFrame("Button", "Atr_BrowserSort_" .. key, window)
		header:SetSize(spec[3], 22)
		header:SetPoint("TOPLEFT", window, "TOPLEFT", 204 + spec[2], -129)
		header:SetNormalFontObject(GameFontNormalSmall)
		header:SetHighlightFontObject(GameFontHighlightSmall)
		header:SetText(spec[1])
		local font = header:GetFontString()
		if font then
			font:ClearAllPoints()
			font:SetPoint("LEFT", header, "LEFT", 0, 0)
			font:SetWidth(spec[3] - 12)
			font:SetJustifyH("LEFT")
		end
		header.arrow = header:CreateTexture(nil, "OVERLAY")
		header.arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
		header.arrow:SetSize(8, 8)
		header.arrow:SetPoint("RIGHT", header, "RIGHT", 0, 0)
		header.arrow:Hide()
		header:SetScript("OnClick", function()
			if sortKey == key then
				descending = not descending
			else
				sortKey = key
				descending = key == "seen"
			end
			applyFilters()
		end)
		headerButtons[key] = header
	end
	scroll = CreateFrame("ScrollFrame", "Atr_BrowserScroll", window, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", window, "TOPLEFT", 202, -158)
	scroll:SetSize(741, 250)
	Atr_StyleAnalysisScroll(scroll, Atr_BrowserResultsBackground)
	scroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, 25, render)
	end)
	for i = 1, 10 do
		local row = CreateFrame("Button", nil, window)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:SetSize(741, 25)
		row:SetPoint("TOPLEFT", window, "TOPLEFT", 204, -158 - (i - 1) * 25)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
		row.stripe = row:CreateTexture(nil, "BACKGROUND")
		row.stripe:SetAllPoints()
		row.stripe:SetTexture(1, 1, 1, i % 2 == 0 and 0.035 or 0)
		row.star = CreateFrame("Button", nil, row)
		row.star:SetSize(20, 22)
		row.star:SetPoint("LEFT", row, "LEFT", 0, 0)
		row.star.texture = row.star:CreateTexture(nil, "ARTWORK")
		row.star.texture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
		row.star.texture:SetSize(16, 16)
		row.star.texture:SetPoint("CENTER", row.star, "CENTER", 0, 0)
		row.star:SetScript("OnClick", function()
			search:ClearFocus()
			if not row.data then
				return
			end
			Atr_ToggleBrowserFavorite(row.data.itemKey or row.data.name)
			GameTooltip:Hide()
			applyFilters(true)
		end)
		row.star:SetScript("OnEnter", function(self)
			if not row.data then
				return
			end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(
				Atr_IsBrowserFavorite(row.data.itemKey or row.data.name)
						and (ZT and ZT("Remove from Favorites") or "Remove from Favorites")
					or (ZT and ZT("Add to Favorites") or "Add to Favorites"),
				1,
				0.82,
				0
			)
			GameTooltip:Show()
		end)
		row.star:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(22, 22)
		row.icon:SetPoint("LEFT", row, "LEFT", 24, 0)
		row.fields = {}
		for col, spec in ipairs(specs) do
			local font = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			font:SetPoint("LEFT", row, "LEFT", spec[2], 0)
			font:SetWidth(spec[3])
			font:SetHeight(22)
			font:SetJustifyH("LEFT")
			row.fields[col] = font
		end
		row:SetScript("OnClick", function(self, mouseButton)
			search:ClearFocus()
			if mouseButton == "RightButton" and self.data then
				if InCombatLockdown and InCombatLockdown() then
					return
				end
				GameTooltip:Hide()
				CloseDropDownMenus()
				shoppingItem = self.data.name
				ToggleDropDownMenu(1, nil, shoppingMenu, "cursor", 0, 0)
				return
			end
			if insertChatLink(self.data) then
				return
			end
			selected = self.data
			updateDetails()
			render()
		end)
		row:SetScript("OnEnter", function(self)
			local entry = self.data
			if not entry then
				return
			end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			tooltipHasPrice = false
			if entry.link then
				GameTooltip:SetHyperlink(entry.link)
			else
				GameTooltip:AddLine(entry.name, 1, 0.82, 0)
			end
			if not tooltipHasPrice then
				GameTooltip:AddLine(
					(ZT and ZT("Saved lowest / item") or "Saved lowest / item") .. ": " .. money(entry.price),
					1,
					1,
					1
				)
				GameTooltip:AddLine((ZT and ZT("Updated") or "Updated") .. ": " .. age(entry.seen), 0.8, 0.8, 0.8)
				if entry.partial then
					GameTooltip:AddLine(
						ZT and ZT("Partial scan price; lower listings may be missing.")
							or "Partial scan price; lower listings may be missing.",
						1,
						0.82,
						0,
						true
					)
				end
				tooltipHasPrice = true
			end
			if entry.historyDays < 3 then
				GameTooltip:AddLine(
					ZT and ZT("* Preliminary: fewer than 3 history days.")
						or "* Preliminary: fewer than 3 history days.",
					1,
					0.82,
					0
				)
			end
			GameTooltip:Show()
		end)
		-- Item-cache/recipe addons can rebuild the tooltip after SetHyperlink.
		-- Restore only our saved-price fallback, without rebuilding the item tip.
		row:SetScript("OnUpdate", function(self)
			if not tooltipHasPrice and self.data and GameTooltip:IsShown() and GameTooltip:GetOwner() == self then
				GameTooltip:AddLine(
					(ZT and ZT("Saved lowest / item") or "Saved lowest / item") .. ": " .. money(self.data.price),
					1,
					1,
					1
				)
				GameTooltip:AddLine((ZT and ZT("Updated") or "Updated") .. ": " .. age(self.data.seen), 0.8, 0.8, 0.8)
				if self.data.partial then
					GameTooltip:AddLine(
						ZT and ZT("Partial scan price; lower listings may be missing.")
							or "Partial scan price; lower listings may be missing.",
						1,
						0.82,
						0,
						true
					)
				end
				tooltipHasPrice = true
				GameTooltip:Show()
			end
		end)
		row:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		rows[i] = row
	end
	countText = text(window, "", 208, -417)
	detailFrame = CreateFrame("Frame", nil, window)
	detailFrame:SetSize(744, 112)
	detailFrame:SetPoint("TOPLEFT", window, "TOPLEFT", 204, -440)
	styleBrowserSurface(detailFrame, true)
	icon = detailFrame:CreateTexture(nil, "ARTWORK")
	icon:SetSize(34, 34)
	icon:SetPoint("TOPLEFT", detailFrame, "TOPLEFT", 10, -10)
	detailName = text(detailFrame, "", 52, -10, "GameFontNormal")
	detailName:SetWidth(370)
	local detailLink = CreateFrame("Button", nil, detailFrame)
	detailLink:SetSize(420, 34)
	detailLink:SetPoint("TOPLEFT", detailFrame, "TOPLEFT", 10, -10)
	detailLink:SetScript("OnClick", function()
		search:ClearFocus()
		insertChatLink(selected)
	end)
	detailInfo = text(detailFrame, "", 52, -30)
	detailInfo:SetSpacing(3)
	detailInfo:SetWidth(265)
	chartButton = button(detailFrame, ZT and ZT("Price chart") or "Price chart", 326, -78, 106, function()
		if selected then
			Atr_ShowPriceChart(selected.name, selected.price, selected.itemKey)
		end
	end)
	chartButton:Disable()
	text(detailFrame, ZT and ZT("Daily lowest prices") or "Daily lowest prices", 450, -10, "GameFontNormalSmall")
	historyScroll = CreateFrame("ScrollFrame", "Atr_BrowserHistoryScroll", detailFrame, "FauxScrollFrameTemplate")
	historyScroll:SetPoint("TOPLEFT", detailFrame, "TOPLEFT", 445, -30)
	historyScroll:SetSize(266, 72)
	historyScroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, 18, renderHistory)
	end)
	local historyBounds = CreateFrame("Frame", "Atr_BrowserHistoryBounds", detailFrame)
	historyBounds:SetPoint("TOPLEFT", detailFrame, "TOPLEFT", 443, -28)
	historyBounds:SetSize(270, 76)
	Atr_StyleAnalysisScroll(historyScroll, historyBounds)
	for i = 1, 4 do
		historyRows[i] = text(detailFrame, "", 450, -30 - (i - 1) * 18)
		historyRows[i]:SetWidth(256)
		historyRows[i]:SetHeight(18)
	end
	metadataStatus = text(window, "", 25, -525, "GameFontDisableSmall")
	metadataStatus:SetWidth(132)
	text(
		window,
		ZT and ZT("Offline prices only. Individual auctions and live stock are not saved.")
			or "Offline prices only. Individual auctions and live stock are not saved.",
		24,
		-574,
		"GameFontDisableSmall"
	)
	button(window, ZT and ZT("Close") or "Close", 836, -566, 115, function()
		window:Hide()
	end)
	updateBackgrounds = function()
		styleBrowserSurface(window, false)
		styleBrowserSurface(Atr_BrowserCategoryBackground, true)
		styleBrowserSurface(Atr_BrowserResultsBackground, true)
		styleBrowserSurface(detailFrame, true)
	end
	window:SetScript("OnShow", function(self)
		backgroundChoice:SetChecked(settings().browserTransparent ~= false)
		updateBackgrounds()
		Atr_StyleAnalysisScroll(scroll, Atr_BrowserResultsBackground)
		Atr_StyleAnalysisScroll(categoryScroll, Atr_BrowserCategoryBackground)
		Atr_StyleAnalysisScroll(historyScroll, Atr_BrowserHistoryBounds)
		local scale = math.min(1, (UIParent:GetWidth() - 30) / 980, (UIParent:GetHeight() - 40) / 600)
		self:SetScale(math.max(0.5, scale))
		search:ClearFocus()
		rebuild()
	end)
	local wasMouseDown = false
	window:SetScript("OnUpdate", function()
		local down = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
		if
			down
			and not wasMouseDown
			and (search:HasFocus() or searchLinkTarget)
			and not MouseIsOver(search)
			and not IsShiftKeyDown()
		then
			searchLinkTarget = false
			search:ClearFocus()
		end
		wasMouseDown = down
	end)
	window:SetScript("OnHide", function()
		searchLinkTarget = false
		CloseDropDownMenus()
		search:ClearFocus()
	end)
	table.insert(UISpecialFrames, "Atr_OfflineBrowser")
	window:Hide()
end
function Atr_ToggleOfflineBrowser()
	if not window then
		createWindow()
	end
	if window:IsShown() then
		window:Hide()
	else
		window:Show()
	end
end

-- Same edge handling as ShardKeeper/IconBox: round quadrants use an
-- outside ellipse; square edges keep the button slightly inside the frame.
AuctionatorRemastered.Legacy.Hook("Atr_Broadcast_DBupdated", function()
	if window and window:IsShown() then
		rebuild()
	end
end)

function Atr_BrowserSetMetadataStatus(message)
	if metadataStatus then
		metadataStatus:SetText(message)
	end
end
function Atr_RefreshOfflineBrowser()
	if window and window:IsShown() then
		rebuild()
	end
end
