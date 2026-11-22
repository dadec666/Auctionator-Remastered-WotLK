-- Deals view. Calculations, shared styling and AH placement live in separate modules.
local panel, scroll, search, summary, empty, advanced
local details, detailsName
local inputs, rows, records, candidates, headers = {}, {}, {}, {}, {}
local categoryScroll, categoryNodes, categoryButtons = nil, {}, {}
local selectedClass, selectedSubclass, selectedSlot, expandedClass, expandedSubclass
local sortBy, descending, dirty, refreshElapsed, ageElapsed = "profit", true, false, 0, 0
local moneyWasShown, artwork = nil, {}
local function settings()
	AUCTIONATOR_SAVEDVARS = AUCTIONATOR_SAVEDVARS or {}
	AUCTIONATOR_SAVEDVARS.deals = Atr_DealsOptions(AUCTIONATOR_SAVEDVARS.deals)
	return AUCTIONATOR_SAVEDVARS.deals
end
local function money(value)
	return gAtrZC.priceToMoneyString(math.floor(value + 0.5))
end
local function ageText(seconds)
	if seconds < 60 then
		return "Now"
	end
	if seconds < 3600 then
		return math.floor(seconds / 60) .. " min"
	end
	return string.format("%.1f h", seconds / 3600)
end
local function showDetails(data)
	detailsName = data and (data.itemKey or data.name) or nil
	if not details then
		return
	end
	details.item:SetText(
		data and data.name or (ZT and ZT("Hover an item to see its deal") or "Hover an item to see its deal")
	)
	local values = data
			and {
				money(data.buy),
				money(data.reference),
				string.format("%.1f%% " .. (ZT and ZT("of usual") or "of usual"), data.market),
				money(data.resale),
				money(data.fee),
				money(data.net),
				(data.profit > 0 and "|cff55dd55" or "|cffffdd55") .. money(data.profit) .. "|r",
				(data.preliminary and "|cffffdd55" or "|cffbbbbbb")
					.. data.days
					.. " "
					.. (ZT and ZT("of") or "of")
					.. " "
					.. Atr_GetMarketHistoryDays()
					.. "|r",
			}
		or {}
	details.labels[2]:SetText((ZT and ZT("Usual price") or "Usual price") .. " (" .. Atr_GetMarketHistoryDays() .. "d)")
	details.labels[5]:SetText((ZT and ZT("AH fee") or "AH fee") .. " (" .. settings().cut .. "%)")
	for i, value in ipairs(details.values) do
		value:SetText(values[i] or "--")
	end
	details.saved:SetText(
		data and ((ZT and ZT("Last scanned:") or "Last scanned:") .. " " .. date("%Y-%m-%d %H:%M", data.when)) or ""
	)
end
local function positionDetails()
	details:ClearAllPoints()
	-- Match the AH's visual size even when its scale differs from UIParent.
	details:SetScale(panel:GetEffectiveScale() / UIParent:GetEffectiveScale())
	details:SetHeight(panel:GetHeight())
	local config = AUCTIONATOR_SAVEDVARS and AUCTIONATOR_SAVEDVARS.dealsDetailPosition
	if AuctionatorRemastered.UI.IsValidPosition(config) then
		local scale = details:GetEffectiveScale() / UIParent:GetEffectiveScale()
		details:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", config.x / scale, config.y / scale)
	else
		-- A separate window, anchored beside AH until the user drags it away.
		details:SetPoint("TOPLEFT", panel, "TOPRIGHT", 12, 0)
		details:SetPoint("BOTTOMLEFT", panel, "BOTTOMRIGHT", 12, 0)
	end
end
local function makeDetails()
	details = CreateFrame("Frame", "Atr_DealsDetails", UIParent)
	details:SetSize(300, 450)
	details:SetFrameStrata("DIALOG")
	details:SetClampedToScreen(true)
	details:SetMovable(true)
	details:EnableMouse(true)
	details:RegisterForDrag("LeftButton")
	details:SetScript("OnDragStart", function(self)
		self:StartMoving()
	end)
	details:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
		AUCTIONATOR_SAVEDVARS = AUCTIONATOR_SAVEDVARS or {}
		AUCTIONATOR_SAVEDVARS.dealsDetailPosition = { x = (self:GetLeft() or 0) * scale, y = (self:GetBottom() or 0)
			* scale }
	end)
	local function text(label, x, y, width, height, font)
		local t = details:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
		t:SetPoint("TOPLEFT", details, "TOPLEFT", x, -y)
		t:SetWidth(width)
		t:SetHeight(height)
		t:SetJustifyH("LEFT")
		t:SetText(label)
		return t
	end
	text(ZT and ZT("Deal details") or "Deal details", 14, 12, 272, 18, "GameFontNormal")
	details.item = text("", 14, 36, 272, 30, "GameFontNormal")
	text(ZT and ZT("Per-item prices") or "Per-item prices", 14, 66, 272, 16, "GameFontNormalSmall")
	text(ZT and ZT("Resale estimate") or "Resale estimate", 14, 138, 272, 16, "GameFontNormalSmall")
	text(ZT and ZT("Price history") or "Price history", 14, 228, 272, 16, "GameFontNormalSmall")
	details.labels, details.values = {}, {}
	local positions = { 84, 100, 116, 158, 174, 190, 206, 248 }
	local dLabels = {
		"Saved buy price",
		"Usual price",
		"Buy vs. usual",
		"Assumed sale price",
		"AH fee",
		"After AH fee",
		"Potential profit",
		"Days recorded",
	}
	for i, label in ipairs(dLabels) do
		local locLabel = ZT and ZT(label) or label
		details.labels[i] = text(locLabel, 14, positions[i], 128, 14, "GameFontHighlightSmall")
		details.values[i] = text("--", 146, positions[i], 140, 14)
	end
	details.saved = text("", 14, 268, 272, 14)
	text(
		ZT and ZT("Estimate only. Check current prices in Buy.\nDeposits and relisting fees are not included.")
			or "Estimate only. Check current prices in Buy.\nDeposits and relisting fees are not included.",
		14,
		290,
		272,
		28,
		"GameFontDisableSmall"
	)
	local actions = {
		{ "Left-click", "Open price chart" },
		{ "Right-click", "Search in Buy" },
		{ "Shift-click", "Link item in chat" },
	}
	for i, action in ipairs(actions) do
		local y = 76 - (i - 1) * 16
		local key = text(ZT and ZT(action[1]) or action[1], 14, 0, 88, 14, "GameFontDisableSmall")
		key:ClearAllPoints()
		key:SetPoint("BOTTOMLEFT", details, "BOTTOMLEFT", 14, y)
		local description = text(ZT and ZT(action[2]) or action[2], 110, 0, 176, 14, "GameFontHighlightSmall")
		description:ClearAllPoints()
		description:SetPoint("BOTTOMLEFT", details, "BOTTOMLEFT", 110, y)
	end
	local reset = CreateFrame("Button", "Atr_DealsDetailsReset", details, "UIPanelButtonTemplate")
	Atr_AnalysisSkin(reset, "Button")
	reset:SetSize(130, 22)
	reset:SetPoint("BOTTOMRIGHT", details, "BOTTOMRIGHT", -14, 12)
	reset:SetText(ZT and ZT("Reset position") or "Reset position")
	reset:SetScript("OnClick", function()
		AUCTIONATOR_SAVEDVARS.dealsDetailPosition = nil
		positionDetails()
	end)
	details:Hide()
end
local function render()
	local visible = math.max(1, math.min(#rows, math.floor((panel:GetHeight() - 154) / 20)))
	FauxScrollFrame_Update(scroll, #records, visible, 20)
	local offset = math.min(FauxScrollFrame_GetOffset(scroll), math.max(0, #records - visible))
	FauxScrollFrame_SetOffset(scroll, offset)
	for i, row in ipairs(rows) do
		local data = records[offset + i]
		row.data = data
		if data and i <= visible then
			row.link = data.link
			row.icon:SetTexture(data.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
			local color = data.market < 95 and "55dd55" or (data.market <= 105 and "ffdd55" or "ff5555")
			local values = {
				data.name,
				money(data.buy),
				(data.profit > 0 and "|cff55dd55" or "|cffffdd55") .. money(data.profit) .. "|r",
				"|cff" .. color .. math.floor(data.market + 0.5) .. "%" .. (data.preliminary and "*" or "") .. "|r",
				ageText(data.age),
			}
			for col, value in ipairs(values) do
				row.fields[col]:SetText(value)
			end
			row:Show()
		else
			row:Hide()
			row.link = nil
		end
	end
end
local function renderCategories()
	categoryNodes = Atr_BuildBrowserCategoryTree(candidates, expandedClass, expandedSubclass)
	local visible = math.max(1, math.min(#categoryButtons, math.floor((panel:GetHeight() - 150) / 22)))
	FauxScrollFrame_Update(categoryScroll, #categoryNodes, visible, 22)
	local offset = math.min(FauxScrollFrame_GetOffset(categoryScroll), math.max(0, #categoryNodes - visible))
	FauxScrollFrame_SetOffset(categoryScroll, offset)
	for i, button in ipairs(categoryButtons) do
		local node = categoryNodes[offset + i]
		button.node = node
		if node and i <= visible then
			local prefix = node.expandable and (node.open and "- " or "+ ") or ""
			local label = node.label == "All items" and "All deals" or node.label
			button:SetText(prefix .. label .. " (" .. node.count .. ")")
			button:SetNormalFontObject(node.depth > 0 and GameFontHighlightSmall or GameFontNormalSmall)
			local font = button:GetFontString()
			local inset = 3 + node.depth * 10
			font:ClearAllPoints()
			font:SetPoint("LEFT", button, "LEFT", inset, 0)
			font:SetWidth(134 - inset)
			font:SetHeight(20)
			font:SetJustifyH("LEFT")
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
local coverage = ""
local function applyFilters(reset)
	records =
		Atr_FilterBrowserSnapshot(candidates, "", selectedClass, sortBy, descending, selectedSubclass, selectedSlot)
	if reset then
		FauxScrollFrame_SetOffset(scroll, 0)
		scroll:SetVerticalScroll(0)
	end
	for key, header in pairs(headers) do
		if sortBy == key then
			header.arrow:SetTexCoord(0, 1, descending and 0 or 1, descending and 1 or 0)
			header.arrow:Show()
		else
			header.arrow:Hide()
		end
	end
	summary:SetText(#records .. " / " .. #candidates .. " deals  |  " .. coverage)
	empty:SetText(#records == 0 and "No deals found.\nTry another category or adjust your search settings." or "")
	render()
	renderCategories()
	local inspected
	for _, entry in ipairs(records) do
		if (entry.itemKey or entry.name) == detailsName then
			inspected = entry
			break
		end
	end
	showDetails(inspected)
end
local function refresh(reset)
	if not panel or not panel:IsShown() then
		dirty = true
		return
	end
	local priced, eligible
	candidates, priced, eligible = Atr_BuildDeals(settings(), search:GetText())
	for _, entry in ipairs(candidates) do
		local stored = (Atr_DatabaseRecord and Atr_DatabaseRecord(entry.itemKey or entry.name))
			or AuctionatorRemastered.Legacy.GetActivePriceDatabase()[entry.name]
		local metadata = Atr_GetBrowserItemMetadata(entry.name, stored)
		entry.link, entry.texture = metadata.link, metadata.texture
		entry.class, entry.subclass, entry.equipLoc = metadata.class, metadata.subclass, metadata.equipLoc
	end
	coverage = eligible .. " eligible  |  " .. priced .. " saved prices"
	dirty = false
	ageElapsed = 0
	applyFilters(reset)
end
local function makePanel()
	local pendingDealsSearch
	panel = CreateFrame("Frame", "Atr_DealsPanel", AuctionFrame)
	panel:SetFrameLevel(AuctionFrame:GetFrameLevel() + 30)
	Atr_AnalysisFit(panel)
	panel:SetBackdrop(nil)
	makeDetails()
	local mover = CreateFrame("Frame", "Atr_AuctionFrameMover", AuctionFrame)
	mover:SetFrameLevel(panel:GetFrameLevel() + 5)
	mover:EnableMouse(true)
	mover:SetPoint("TOPLEFT", panel, "TOPLEFT", 80, 0)
	mover:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -60, 0)
	mover:SetHeight(26)
	mover:RegisterForDrag("LeftButton")
	-- Reanchor the handle to the ordinary shell when the Deals overlay hides.
	mover:SetScript("OnShow", function(self)
		local base = (AuctionFrame.backdrop and AuctionFrameBrowse and AuctionFrameBrowse.RightBackground)
				and AuctionFrame.backdrop
			or AuctionFrame
		self:ClearAllPoints()
		self:SetPoint("TOPLEFT", base, "TOPLEFT", 80, 0)
		self:SetPoint("TOPRIGHT", base, "TOPRIGHT", -60, 0)
	end)
	mover:GetScript("OnShow")(mover)
	local function text(label, x, y, template, parent)
		parent = parent or panel
		local t = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
		t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
		t:SetText(label)
		return t
	end
	local function button(name, label, x, y, width, callback, parent)
		parent = parent or panel
		local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
		Atr_AnalysisSkin(b, "Button")
		b:SetSize(width, 22)
		b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
		b:SetText(label)
		b:SetScript("OnClick", callback)
		return b
	end
	local function Z(s)
		return ZT and ZT(s) or s
	end
	local title = text(Z("Deals"), 0, 0, "GameFontNormal")
	title:ClearAllPoints()
	title:SetPoint("TOP", panel, "TOP", 0, -10)
	panel.results = CreateFrame("Frame", nil, panel)
	panel.results:SetFrameLevel(panel:GetFrameLevel())
	panel.results:SetPoint("TOPLEFT", panel, "TOPLEFT", 178, -106)
	panel.results:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 40)
	panel.sidebar = CreateFrame("Frame", "Atr_DealsCategories", panel)
	panel.sidebar:SetFrameLevel(panel:GetFrameLevel())
	panel.sidebar:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -106)
	panel.sidebar:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 40)
	panel.sidebar:SetWidth(142)
	local function resultStyle()
		local source = AuctionFrameBrowse and AuctionFrameBrowse.RightBackground
		for _, surface in ipairs({ panel.results, panel.sidebar }) do
			if source and source.GetBackdrop and source:GetBackdrop() then
				surface:SetBackdrop(source:GetBackdrop())
				surface:SetBackdropColor(source:GetBackdropColor())
				if source.GetBackdropBorderColor then
					surface:SetBackdropBorderColor(source:GetBackdropBorderColor())
				end
			else
				Atr_AnalysisBackdrop(surface, 1)
			end
		end
	end
	resultStyle()
	local close = button("Atr_DealsCloseButton", Z("Close"), 0, 0, 80, function()
		HideUIPanel(AuctionFrame)
	end)
	close:ClearAllPoints()
	close:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 10)

	advanced = CreateFrame("Frame", "Atr_DealsAdvanced", panel)
	advanced:SetSize(440, 214)
	advanced:SetPoint("CENTER", panel, "CENTER", 0, 0)
	advanced:SetFrameLevel(panel:GetFrameLevel() + 10)
	advanced:EnableMouse(true)
	Atr_AnalysisBackdrop(advanced, 1)
	if UISpecialFrames then
		table.insert(UISpecialFrames, "Atr_DealsAdvanced")
	end
	local heading = text("Deal settings", 0, 0, "GameFontNormal", advanced)
	heading:ClearAllPoints()
	heading:SetPoint("TOP", advanced, "TOP", 0, -12)
	button(nil, "Done", 340, -180, 80, function()
		advanced:Hide()
	end, advanced)
	advanced:SetScript("OnHide", function()
		for _, input in pairs(inputs) do
			input:ClearFocus()
		end
	end)
	advanced:Hide()
	local specs = {
		{ "Max Market %", "maxMarket", "Show listings at or below this percentage of the existing market reference." },
		{
			"Min profit (g)",
			"minProfit",
			"Minimum estimated profit per item after the selected AH cut. Deposits and relisting costs are excluded.",
		},
		{
			"Max age (h)",
			"maxAge",
			"Only use saved prices this many hours old or newer. Items without a trustworthy timestamp are excluded.",
		},
		{
			"Min history (days)",
			"minDays",
			"Available prior days inside your market-reference window. Set 0 to include preliminary references, marked with *.",
		},
		{
			"Resell at (% ref)",
			"resale",
			"Assumed resale price as a percentage of the reference. This is a planning estimate, not an observed sale.",
		},
		{
			"AH cut %",
			"cut",
			"Sale commission used for estimates. Set it to the fee for your auction house (usually 5; neutral houses may differ).",
		},
	}
	local opts = settings()
	for i, spec in ipairs(specs) do
		local key = spec[2]
		local parent = i <= 2 and panel or advanced
		local x = i <= 2 and (300 + (i - 1) * 120) or (24 + (i - 3) % 2 * 210)
		local y = i <= 2 and -30 or (-44 - math.floor((i - 3) / 2) * 62)
		text(Z(spec[1]), x, y, nil, parent)
		local input = CreateFrame("EditBox", "Atr_DealsFilter_" .. key, parent, "InputBoxTemplate")
		Atr_AnalysisSkin(input, "EditBox")
		input:SetSize(i <= 2 and 95 or 160, 22)
		input:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 4, y - 18)
		input:SetAutoFocus(false)
		input:SetMaxLetters(9)
		input:SetText(tostring(opts[key]))
		inputs[key] = input
		local function commit(self)
			local values = settings()
			values[key] = self:GetText()
			values = Atr_DealsOptions(values)
			AUCTIONATOR_SAVEDVARS.deals = values
			self:SetText(tostring(values[key]))
			refresh(true)
		end
		input:SetScript("OnEditFocusLost", commit)
		input:SetScript("OnEnterPressed", function(self)
			self:ClearFocus()
		end)
		input:SetScript("OnEscapePressed", function(self)
			self:SetText(tostring(settings()[key]))
			self:ClearFocus()
		end)
		input:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(Z(spec[1]))
			GameTooltip:AddLine(Z(spec[3]), 1, 1, 1, true)
			GameTooltip:Show()
		end)
		input:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
	end
	text(Z("Name"), 20, -30)
	search = CreateFrame("EditBox", "Atr_DealsSearch", panel, "InputBoxTemplate")
	Atr_AnalysisSkin(search, "EditBox")
	search:SetSize(240, 22)
	search:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, -48)
	search:SetAutoFocus(false)
	search:SetScript("OnTextChanged", function(self)
		if self.HasFocus and self:HasFocus() then
			pendingDealsSearch = 0.2
		else
			pendingDealsSearch = nil
			refresh(true)
		end
	end)
	search:SetScript("OnEscapePressed", function(self)
		pendingDealsSearch = nil
		self:ClearFocus()
	end)
	search:SetScript("OnEnterPressed", function(self)
		pendingDealsSearch = nil
		refresh(true)
		self:ClearFocus()
	end)
	search:SetScript("OnUpdate", function(self, elapsed)
		if pendingDealsSearch then
			pendingDealsSearch = pendingDealsSearch - elapsed
			if pendingDealsSearch <= 0 then
				pendingDealsSearch = nil
				refresh(true)
			end
		end
	end)
	local settingsButton = button("Atr_DealsSettings", Z("Settings"), 550, -48, 100, function()
		search:ClearFocus()
		if advanced:IsShown() then
			advanced:Hide()
		else
			advanced:Show()
		end
	end)
	settingsButton:SetScript("OnEnter", function(self)
		local values = settings()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(Z("Deal settings"))
		for i = 3, #specs do
			GameTooltip:AddLine(Z(specs[i][1]) .. ": " .. values[specs[i][2]], 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	settingsButton:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	button("Atr_DealsClearSearch", Z("Clear search"), 660, -48, 110, function()
		pendingDealsSearch = nil
		search:SetText("")
		search:ClearFocus()
		refresh(true)
	end)
	text(Z("Categories"), 20, -90)
	summary = text("", 20, 0, "GameFontHighlightSmall")
	summary:ClearAllPoints()
	summary:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 20, 22)
	summary:SetWidth(650)
	summary:SetHeight(14)
	summary:SetJustifyH("LEFT")
	local cols = {
		{ "Item", 208, 154, "name" },
		{ "Saved buy", 368, 110, "buy" },
		{ "Est. profit", 504, 118, "profit" },
		{ "Market %", 642, 70, "market" },
		{ "Updated", 718, 58, "when" },
	}
	for _, spec in ipairs(cols) do
		local key = spec[4]
		local header = CreateFrame("Button", "Atr_DealsSort_" .. key, panel)
		header:SetPoint("TOPLEFT", panel, "TOPLEFT", spec[2], -86)
		header:SetSize(spec[3], 18)
		header:SetNormalFontObject(GameFontNormalSmall)
		header:SetHighlightFontObject(GameFontHighlightSmall)
		header.label = spec[1]
		header:SetText(Z(spec[1]))
		headers[key] = header
		local font = header:GetFontString()
		font:ClearAllPoints()
		font:SetHeight(18)
		if font.SetWordWrap then
			font:SetWordWrap(false)
		end
		font:SetPoint("LEFT", header, "LEFT", 0, 0)
		font:SetWidth(spec[3] - 10)
		font:SetJustifyH("LEFT")
		header.arrow = header:CreateTexture(nil, "OVERLAY")
		header.arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
		header.arrow:SetSize(8, 8)
		header.arrow:SetPoint("RIGHT", header, "RIGHT", 0, 0)
		header.arrow:Hide()
		header:SetScript("OnClick", function()
			search:ClearFocus()
			if sortBy == key then
				descending = not descending
			else
				sortBy = key
				descending = key == "profit" or key == "when"
			end
			applyFilters(true)
		end)
	end
	scroll = CreateFrame("ScrollFrame", "Atr_DealsScroll", panel, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 182, -110)
	scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -32, 44)
	Atr_StyleAnalysisScroll(scroll, panel.results)
	scroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, 20, render)
	end)
	categoryScroll = CreateFrame("ScrollFrame", "Atr_DealsCategoryScroll", panel, "FauxScrollFrameTemplate")
	categoryScroll:SetPoint("TOPLEFT", panel.sidebar, "TOPLEFT", 4, -4)
	categoryScroll:SetPoint("BOTTOMRIGHT", panel.sidebar, "BOTTOMRIGHT", -4, 4)
	Atr_StyleAnalysisScroll(categoryScroll, panel.sidebar)
	categoryScroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, 22, renderCategories)
	end)
	for i = 1, 24 do
		local b = CreateFrame("Button", "Atr_DealsCategory" .. i, panel)
		b:SetPoint("TOPLEFT", panel.sidebar, "TOPLEFT", 4, -4 - (i - 1) * 22)
		b:SetSize(134, 22)
		b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
		b:SetHighlightFontObject(GameFontHighlightSmall)
		b:SetScript("OnClick", function(self)
			local node = self.node
			if not node then
				return
			end
			search:ClearFocus()
			selectedClass, selectedSubclass, selectedSlot = node.class, node.subclass, node.slot
			if node.depth == 0 then
				expandedClass = node.expandable and (expandedClass ~= node.class and node.class or nil) or nil
				expandedSubclass = nil
			elseif node.depth == 1 then
				expandedSubclass = node.expandable and (expandedSubclass ~= node.subclass and node.subclass or nil)
					or nil
			end
			applyFilters(true)
		end)
		categoryButtons[i] = b
	end
	for i = 1, 24 do
		local row = CreateFrame("Button", nil, panel)
		row:SetPoint("TOPLEFT", panel, "TOPLEFT", 182, -110 - (i - 1) * 20)
		row:SetPoint("RIGHT", panel, "RIGHT", -32, 0)
		row:SetHeight(20)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
		local stripe = row:CreateTexture(nil, "BACKGROUND")
		stripe:SetAllPoints()
		stripe:SetTexture(1, 1, 1, i % 2 == 0 and 0.035 or 0)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(18, 18)
		row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
		row.fields = {}
		for col, spec in ipairs(cols) do
			local font = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			font:SetPoint("LEFT", row, "LEFT", spec[2] - 182, 0)
			font:SetWidth(spec[3])
			font:SetHeight(18)
			font:SetJustifyH("LEFT")
			row.fields[col] = font
		end
		row:SetScript("OnEnter", function(self)
			local d = self.data
			if not d then
				return
			end
			showDetails(d)
			-- Resolve again on hover in case the client cache filled after the
			-- last refresh. Only exact observed links are used for suffix items.
			local stored = (Atr_DatabaseRecord and Atr_DatabaseRecord(d.itemKey or d.name))
				or (gAtr_ScanDB and gAtr_ScanDB[d.name])
			local metadata = Atr_GetBrowserItemMetadata(d.name, stored)
			local link = metadata.link or self.link
			GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
			local ok = link and pcall(GameTooltip.SetHyperlink, GameTooltip, link)
			if not ok or not GameTooltip:GetItem() then
				GameTooltip:ClearLines()
				GameTooltip:AddLine(d.name, 1, 0.82, 0)
				GameTooltip:AddLine("Item information is not cached yet.", 0.8, 0.8, 0.8, true)
			end
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		row:SetScript("OnClick", function(self, button)
			if not self.data then
				return
			end
			if button == "RightButton" then
				AuctionatorRemastered.Legacy.SearchBuyExact(self.data.name)
			elseif IsShiftKeyDown() then
				if self.link and Atr_InsertChatLink then
					Atr_InsertChatLink(self.link)
				end
			elseif Atr_ShowPriceChart then
				Atr_ShowPriceChart(self.data.name, self.data.buy, self.data.itemKey)
			end
		end)
		rows[i] = row
	end
	empty = text("", 0, 0, "GameFontNormal")
	empty:ClearAllPoints()
	empty:SetPoint("TOPLEFT", panel.results, "TOPLEFT", 16, -34)
	empty:SetPoint("TOPRIGHT", panel.results, "TOPRIGHT", -16, -34)
	empty:SetJustifyH("CENTER")
	local footer = text(
		"Saved prices per item. Check current prices in Buy. Deposits and relisting fees excluded.",
		20,
		0,
		"GameFontDisableSmall"
	)
	footer:ClearAllPoints()
	footer:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 20, 7)
	footer:SetWidth(650)
	footer:SetHeight(12)
	footer:SetJustifyH("LEFT")
	panel:SetScript("OnShow", function()
		Atr_AnalysisFit(panel)
		artwork = Atr_AnalysisBegin(panel)
		resultStyle()
		Atr_StyleAnalysisScroll(scroll, panel.results)
		Atr_StyleAnalysisScroll(categoryScroll, panel.sidebar)
		moneyWasShown = AuctionFrameMoneyFrame and AuctionFrameMoneyFrame:IsShown()
		if AuctionFrameMoneyFrame then
			AuctionFrameMoneyFrame:Hide()
		end
		refresh(true)
		Atr_StyleOfflineBrowser(details, false)
		positionDetails()
		details:Show()
	end)
	panel:SetScript("OnHide", function()
		pendingDealsSearch = nil
		advanced:Hide()
		details:Hide()
		detailsName = nil
		Atr_AnalysisEnd(artwork)
		artwork = {}
		if moneyWasShown and AuctionFrameMoneyFrame then
			AuctionFrameMoneyFrame:Show()
		end
		moneyWasShown = nil
		for _, input in pairs(inputs) do
			input:ClearFocus()
		end
		search:ClearFocus()
		GameTooltip:Hide()
	end)
	panel:SetScript("OnUpdate", function(_, elapsed)
		refreshElapsed = refreshElapsed + elapsed
		ageElapsed = ageElapsed + elapsed
		if refreshElapsed >= 1 then
			refreshElapsed = 0
			if dirty or ageElapsed >= 60 then
				refresh(false)
			end
		end
	end)
	panel:Hide()
	AuctionatorRemastered.UI.SetupAppearance(mover, positionDetails, settings)
end
AuctionatorRemastered.Legacy.Hook("Atr_Broadcast_DBupdated", function()
	dirty = true
end)
AuctionatorRemastered.Legacy.Hook("Atr_Init", function()
	makePanel()
	local n = AuctionFrame.numTabs + 1
	local tab = CreateFrame("Button", "AuctionFrameTab" .. n, AuctionFrame, "AuctionTabTemplate")
	tab:SetID(n)
	tab:SetText(ZT and ZT("Deals") or "Deals")
	tab:SetNormalFontObject(AtrFontOrange)
	PanelTemplates_TabResize(tab, 0)
	tab:SetPoint("LEFT", _G["AuctionFrameTab" .. (n - 1)], "RIGHT", -8, 0)
	PanelTemplates_SetNumTabs(AuctionFrame, n)
	PanelTemplates_EnableTab(AuctionFrame, n)
	tab:SetScript("OnClick", function()
		Atr_AuctionFrameTab_OnClick(AuctionFrameTab1, 1)
		AuctionFrameBrowse:Hide()
		AuctionFrameBid:Hide()
		AuctionFrameAuctions:Hide()
		Atr_Main_Panel:Hide()
		PanelTemplates_SetTab(AuctionFrame, n)
		panel:Show()
	end)
end)
