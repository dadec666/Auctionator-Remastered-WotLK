-- SellTerminal.lua: Modern 3-Column Sell Terminal for Auctionator Remastered (WoW 3.3.5a)
-- Integrated 3-column layout expanding AuctionFrame:
-- Column 1: Bag Inventory Sidebar (Scan bags 0..4, Soulbound/BoP/Quest filter, grouping, total value, instant search, categories)
-- Column 2: Staging & Posting Controls (Item header, Reference pricing cards, Quick prices, Buyout/Bid inputs, Stacking presets, Duration, Post button)
-- Column 3: Live Market Competitors (Competitor prices, Stacks, Seller, Undercut status, Click-to-copy price, Refresh button)

local panel, bagScroll, competitorsScroll
local searchBox, clearSearchBtn
local stagedIcon, stagedName, stagedCounts
local refLowVal, refMarketVal, refVendorVal
local buyoutGold, buyoutSilver, buyoutCopper
local bidGold, bidSilver, bidCopper
local stackSizeEdit, numStacksEdit
local durationButtons = {}
local depositVal, netRevenueVal, postBtn
local compStatusBadge, compHeaderTitle
local categoryButtons = {}
local artwork = {}

local bagItems = {}
local filteredBagItems = {}
local bagRows = {}
local compRows = {}

local stagedItem = nil
local selectedCategory = "ALL"
local selectedDuration = 1
local priceMode = "unit" -- "unit" or "stack"
local bagScanDirty = true
local bagScanThrottle = 0

local function Z(s)
	return (ZT and ZT(s)) or s
end

local function money(v)
	if not v or v <= 0 then
		return "0|cffffd100g|r"
	end
	if gAtrZC and gAtrZC.priceToMoneyString then
		return gAtrZC.priceToMoneyString(math.floor(v + 0.5))
	end
	local g = math.floor(v / 10000)
	local s = math.floor((v % 10000) / 100)
	local c = math.floor(v % 100)
	if g > 0 then
		return string.format("%d|cffffd100g|r %02d|cffe6e6e6s|r %02d|cffc79c6ec|r", g, s, c)
	elseif s > 0 then
		return string.format("%d|cffe6e6e6s|r %02d|cffc79c6ec|r", s, c)
	else
		return string.format("%d|cffc79c6ec|r", c)
	end
end

-- ============================================================================
-- Soulbound & Unsellable Item Filter
-- ============================================================================
local function IsItemSoulbound(bag, slot)
	local tip = _G["AtrScanningTooltip"] or _G["AtrScanningTooltip2"]
	if not tip then
		tip = CreateFrame("GameTooltip", "AtrSellTerminalScanTip", UIParent, "GameTooltipTemplate")
		tip:SetOwner(WorldFrame, "ANCHOR_NONE")
	end
	tip:ClearLines()
	local ok = pcall(tip.SetBagItem, tip, bag, slot)
	if not ok then
		return false
	end

	local numLines = tip:NumLines() or 0
	local tipName = tip:GetName()
	for i = 2, numLines do
		local line = _G[tipName .. "TextLeft" .. i]
		if line then
			local text = line:GetText()
			if text then
				if
					text == ITEM_SOULBOUND
					or text == ITEM_BIND_ON_PICKUP
					or text == ITEM_BIND_QUEST
					or text == ITEM_BIND_TO_ACCOUNT
					or text == ITEM_CONJURED
					or (ITEM_BIND_TO_BNETACCOUNT and text == ITEM_BIND_TO_BNETACCOUNT)
				then
					return true
				end
			end
		end
	end
	return false
end

-- ============================================================================
-- Bag Inventory Scanning & Grouping
-- ============================================================================
local function ScanPlayerBags()
	bagItems = {}
	local itemMap = {}

	local numBags = NUM_BAG_SLOTS or 4
	for bag = 0, numBags do
		local numSlots = GetContainerNumSlots(bag) or 0
		for slot = 1, numSlots do
			local itemLink = GetContainerItemLink(bag, slot)
			if itemLink then
				local texture, itemCount, locked, quality = GetContainerItemInfo(bag, slot)
				-- Fully filter out soulbound, BoP, quest, and conjured items
				if not IsItemSoulbound(bag, slot) and (quality or 0) > 0 then
					local itemName, _, itemRarity, _, _, itemType, itemSubType, maxStack, _, _, itemVendorPrice =
						GetItemInfo(itemLink)
					if itemName then
						local itemKey = (zc and zc.ItemIDStrfromLink and zc.ItemIDStrfromLink(itemLink)) or itemName
						local entry = itemMap[itemKey]
						if not entry then
							local marketPrice = (Atr_GetAuctionPrice and Atr_GetAuctionPrice(itemKey or itemName))
								or (Atr_MarketReference and Atr_MarketReference(itemName))
								or 0
							local unitPrice = (marketPrice > 0 and marketPrice) or (itemVendorPrice or 0)
							entry = {
								key = itemKey,
								link = itemLink,
								name = itemName,
								texture = texture,
								quality = itemRarity or quality or 1,
								type = itemType or "",
								subType = itemSubType or "",
								maxStack = maxStack or 1,
								vendorPrice = itemVendorPrice or 0,
								marketPrice = marketPrice or 0,
								unitPrice = unitPrice,
								totalCount = 0,
								totalValue = 0,
								slots = {},
							}
							itemMap[itemKey] = entry
							bagItems[#bagItems + 1] = entry
						end
						entry.totalCount = entry.totalCount + (itemCount or 1)
						entry.slots[#entry.slots + 1] = { bag = bag, slot = slot, count = itemCount or 1 }
					end
				end
			end
		end
	end

	-- Compute total values
	for _, item in ipairs(bagItems) do
		item.totalValue = item.unitPrice * item.totalCount
	end

	Atr_FilterBagItems()
end

function Atr_FilterBagItems()
	filteredBagItems = {}
	local search = searchBox and searchBox:GetText() or ""
	search = string.lower(string.trim and string.trim(search) or search)

	for _, item in ipairs(bagItems) do
		local matchesCategory = true
		if selectedCategory == "TRADE" then
			matchesCategory = (item.type == "Trade Goods" or item.type == "Gem" or item.type == "Recipe")
		elseif selectedCategory == "EQUIP" then
			matchesCategory = (item.type == "Armor" or item.type == "Weapon")
		elseif selectedCategory == "CONSUMABLE" then
			matchesCategory = (item.type == "Consumable")
		end

		local matchesSearch = true
		if search ~= "" then
			matchesSearch = string.find(string.lower(item.name), search, 1, true) ~= nil
		end

		if matchesCategory and matchesSearch then
			filteredBagItems[#filteredBagItems + 1] = item
		end
	end

	-- Default sorting: Total Value descending
	table.sort(filteredBagItems, function(a, b)
		if a.totalValue ~= b.totalValue then
			return a.totalValue > b.totalValue
		end
		return a.name < b.name
	end)

	Atr_RenderBagInventory()
end

function Atr_RenderBagInventory()
	if not bagScroll then
		return
	end

	local numRecords = #filteredBagItems
	local visibleRows = #bagRows
	FauxScrollFrame_Update(bagScroll, numRecords, visibleRows, 33)

	local offset = FauxScrollFrame_GetOffset(bagScroll)
	for i, row in ipairs(bagRows) do
		local index = offset + i
		local data = filteredBagItems[index]
		row.data = data
		if data and index <= numRecords then
			row.icon:SetTexture(data.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
			if data.totalCount > 1 then
				row.countText:SetText(data.totalCount)
				row.countText:Show()
			else
				row.countText:Hide()
			end

			local r, g, b = GetItemQualityColor(data.quality or 1)
			row.nameText:SetText(data.name)
			row.nameText:SetTextColor(r or 1, g or 1, b or 1)

			row.priceText:SetText(money(data.unitPrice))
			row.valueText:SetText(money(data.totalValue))
			row:Show()
		else
			row:Hide()
			row.data = nil
		end
	end
end

-- ============================================================================
-- Staging Logic (Column 2)
-- ============================================================================
local function GetInputBuyout()
	local g = buyoutGold and buyoutGold:GetNumber() or 0
	local s = buyoutSilver and buyoutSilver:GetNumber() or 0
	local c = buyoutCopper and buyoutCopper:GetNumber() or 0
	return (g * 10000) + (s * 100) + c
end

local function SetInputBuyout(copper)
	copper = math.max(0, math.floor((copper or 0) + 0.5))
	local g = math.floor(copper / 10000)
	local s = math.floor((copper % 10000) / 100)
	local c = math.floor(copper % 100)
	if buyoutGold then
		buyoutGold:SetText(g > 0 and g or "")
	end
	if buyoutSilver then
		buyoutSilver:SetText((g > 0 or s > 0) and s or "")
	end
	if buyoutCopper then
		buyoutCopper:SetText(copper > 0 and c or "")
	end
end

local function GetInputBid()
	local g = bidGold and bidGold:GetNumber() or 0
	local s = bidSilver and bidSilver:GetNumber() or 0
	local c = bidCopper and bidCopper:GetNumber() or 0
	return (g * 10000) + (s * 100) + c
end

local function SetInputBid(copper)
	copper = math.max(0, math.floor((copper or 0) + 0.5))
	local g = math.floor(copper / 10000)
	local s = math.floor((copper % 10000) / 100)
	local c = math.floor(copper % 100)
	if bidGold then
		bidGold:SetText(g > 0 and g or "")
	end
	if bidSilver then
		bidSilver:SetText((g > 0 or s > 0) and s or "")
	end
	if bidCopper then
		bidCopper:SetText(copper > 0 and c or "")
	end
end

local function GetStagedStackSize()
	return stackSizeEdit and stackSizeEdit:GetNumber() or 1
end

local function GetStagedNumStacks()
	return numStacksEdit and numStacksEdit:GetNumber() or 1
end

local function RecalculateEstimates()
	if not stagedItem then
		if depositVal then
			depositVal:SetText("--")
		end
		if netRevenueVal then
			netRevenueVal:SetText("--")
		end
		return
	end

	local size = math.max(1, GetStagedStackSize())
	local count = math.max(1, GetStagedNumStacks())
	local buyoutPerStack = GetInputBuyout()
	if priceMode == "unit" then
		buyoutPerStack = buyoutPerStack * size
	end

	-- Calculate deposit
	local deposit = 0
	if CalculateAuctionDeposit then
		deposit = CalculateAuctionDeposit(selectedDuration, size * count)
	end
	if depositVal then
		depositVal:SetText(money(deposit))
	end

	-- Calculate net revenue after 5% AH cut
	local grossRevenue = buyoutPerStack * count
	local netRevenue = math.floor(grossRevenue * 0.95)
	if netRevenueVal then
		netRevenueVal:SetText(money(netRevenue))
	end
end

local function UpdateStagedPricingCards()
	if not stagedItem then
		if refLowVal then
			refLowVal:SetText("--")
		end
		if refMarketVal then
			refMarketVal:SetText("--")
		end
		if refVendorVal then
			refVendorVal:SetText("--")
		end
		return
	end

	-- Vendor price
	if refVendorVal then
		refVendorVal:SetText(money(stagedItem.vendorPrice or 0))
	end

	-- Market reference
	local marketRef = (Atr_MarketReference and Atr_MarketReference(stagedItem.name))
		or (Atr_GetAuctionPrice and Atr_GetAuctionPrice(stagedItem.name))
		or 0
	if refMarketVal then
		refMarketVal:SetText(marketRef > 0 and money(marketRef) or "|cff888888--|r")
	end

	-- Lowest buyout from current scan
	local lowestBuyout = nil
	if gSellPane and gSellPane.activeScan and gSellPane.activeScan.sortedData then
		for _, entry in ipairs(gSellPane.activeScan.sortedData) do
			if entry.type == "n" and (entry.buyoutPrice or 0) > 0 then
				local unitBuyout = entry.buyoutPrice / math.max(1, entry.stackSize or 1)
				if not lowestBuyout or unitBuyout < lowestBuyout then
					lowestBuyout = unitBuyout
				end
			end
		end
	end
	if refLowVal then
		refLowVal:SetText(lowestBuyout and money(lowestBuyout) or "|cff888888--|r")
	end
end

local function UpdateStagedDisplay()
	if not stagedItem then
		if stagedIcon then
			stagedIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		end
		if stagedName then
			stagedName:SetText("|cff888888" .. Z("No item selected") .. "|r")
		end
		if stagedCounts then
			stagedCounts:SetText(Z("Select an item from your bags or drop it here"))
		end
		SetInputBuyout(0)
		SetInputBid(0)
		if stackSizeEdit then
			stackSizeEdit:SetText("")
		end
		if numStacksEdit then
			numStacksEdit:SetText("")
		end
		if postBtn then
			postBtn:Disable()
		end
		UpdateStagedPricingCards()
		RecalculateEstimates()
		Atr_RenderCompetitors()
		return
	end

	if stagedIcon then
		stagedIcon:SetTexture(stagedItem.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
	end
	local r, g, b = GetItemQualityColor(stagedItem.quality or 1)
	if stagedName then
		stagedName:SetText(stagedItem.name)
		stagedName:SetTextColor(r or 1, g or 1, b or 1)
	end
	if stagedCounts then
		stagedCounts:SetText(
			string.format(Z("In bags: %d"), stagedItem.totalCount)
				.. "   |   "
				.. string.format(Z("Max stack: %d"), stagedItem.maxStack)
		)
	end

	-- Initial stacking: full stacks
	local stackSize = math.min(stagedItem.totalCount, stagedItem.maxStack)
	local numStacks = math.max(1, math.floor(stagedItem.totalCount / stackSize))
	if stackSizeEdit then
		stackSizeEdit:SetText(stackSize)
	end
	if numStacksEdit then
		numStacksEdit:SetText(numStacks)
	end

	-- Initial price
	local initPrice = stagedItem.marketPrice > 0 and stagedItem.marketPrice or (stagedItem.vendorPrice * 3)
	SetInputBuyout(initPrice)
	local startBid = (Atr_CalcStartPrice and Atr_CalcStartPrice(initPrice)) or math.floor(initPrice * 0.95)
	SetInputBid(startBid)

	if postBtn then
		postBtn:Enable()
	end

	UpdateStagedPricingCards()
	RecalculateEstimates()
end

local function StageBagItem(item)
	if not item or not item.slots or #item.slots == 0 then
		return
	end
	stagedItem = item

	local first = item.slots[1]
	ClearCursor()
	PickupContainerItem(first.bag, first.slot)
	if GetCursorInfo() == "item" then
		if Atr_ClickAuctionSellItemButton then
			Atr_ClickAuctionSellItemButton()
		else
			ClickAuctionSellItemButton()
		end
		ClearCursor()
	end

	UpdateStagedDisplay()
end

-- ============================================================================
-- Quick Stacking & Pricing Actions
-- ============================================================================
local function ApplyQuickPrice(mode)
	if not stagedItem then
		return
	end

	local targetPrice = 0
	local lowestBuyout = nil
	if gSellPane and gSellPane.activeScan and gSellPane.activeScan.sortedData then
		for _, entry in ipairs(gSellPane.activeScan.sortedData) do
			if entry.type == "n" and (entry.buyoutPrice or 0) > 0 then
				local unitBuyout = entry.buyoutPrice / math.max(1, entry.stackSize or 1)
				if not lowestBuyout or unitBuyout < lowestBuyout then
					lowestBuyout = unitBuyout
				end
			end
		end
	end

	local marketRef = (Atr_MarketReference and Atr_MarketReference(stagedItem.name))
		or (Atr_GetAuctionPrice and Atr_GetAuctionPrice(stagedItem.name))
		or 0

	if mode == "undercut" then
		if lowestBuyout and lowestBuyout > 1 then
			targetPrice = lowestBuyout - 1
		elseif marketRef > 1 then
			targetPrice = marketRef - 1
		else
			targetPrice = math.max(1, stagedItem.vendorPrice)
		end
	elseif mode == "match" then
		if lowestBuyout and lowestBuyout > 0 then
			targetPrice = lowestBuyout
		elseif marketRef > 0 then
			targetPrice = marketRef
		else
			targetPrice = stagedItem.vendorPrice
		end
	elseif mode == "market" then
		if marketRef > 0 then
			targetPrice = marketRef
		elseif lowestBuyout and lowestBuyout > 0 then
			targetPrice = lowestBuyout
		else
			targetPrice = stagedItem.vendorPrice
		end
	end

	SetInputBuyout(targetPrice)
	local startBid = (Atr_CalcStartPrice and Atr_CalcStartPrice(targetPrice)) or math.floor(targetPrice * 0.95)
	SetInputBid(startBid)
	RecalculateEstimates()
end

local function ApplyQuickStacking(preset)
	if not stagedItem then
		return
	end
	local total = stagedItem.totalCount or 1
	local maxStack = stagedItem.maxStack or 1

	if preset == "all" then
		local size = math.min(total, maxStack)
		local count = math.max(1, math.floor(total / size))
		if stackSizeEdit then
			stackSizeEdit:SetText(size)
		end
		if numStacksEdit then
			numStacksEdit:SetText(count)
		end
	elseif preset == "singles" then
		if stackSizeEdit then
			stackSizeEdit:SetText(1)
		end
		if numStacksEdit then
			numStacksEdit:SetText(total)
		end
	elseif preset == "full" then
		local count = math.max(1, math.floor(total / maxStack))
		if stackSizeEdit then
			stackSizeEdit:SetText(maxStack)
		end
		if numStacksEdit then
			numStacksEdit:SetText(count)
		end
	end
	RecalculateEstimates()
end

-- ============================================================================
-- Column 3: Live Market Competitors
-- ============================================================================
function Atr_RenderCompetitors()
	if not competitorsScroll then
		return
	end

	local list = {}
	if gSellPane and gSellPane.activeScan and gSellPane.activeScan.sortedData then
		for _, entry in ipairs(gSellPane.activeScan.sortedData) do
			if entry.type == "n" then
				list[#list + 1] = entry
			end
		end
	end

	-- Status badge evaluation
	if not stagedItem or #list == 0 then
		if compStatusBadge then
			compStatusBadge:SetText("|cff55aaff● " .. Z("No Competitors") .. "|r")
		end
	else
		local playerLowest = false
		local undercut = false
		local currentBuyout = GetInputBuyout()
		local lowestComp = list[1]
		local lowestUnit = lowestComp and (lowestComp.buyoutPrice / math.max(1, lowestComp.stackSize or 1))

		if lowestComp and lowestComp.yours then
			playerLowest = true
		elseif lowestUnit and currentBuyout > lowestUnit then
			undercut = true
		end

		if compStatusBadge then
			if playerLowest or (lowestUnit and currentBuyout <= lowestUnit) then
				compStatusBadge:SetText("|cff55dd55● " .. Z("Lowest Price!") .. "|r")
			elseif undercut then
				compStatusBadge:SetText("|cffffaa55● " .. Z("You are undercut!") .. "|r")
			else
				compStatusBadge:SetText("|cff55aaff● " .. Z("Market Active") .. "|r")
			end
		end
	end

	local numRecords = #list
	local visibleRows = #compRows
	FauxScrollFrame_Update(competitorsScroll, numRecords, visibleRows, 26)

	local offset = FauxScrollFrame_GetOffset(competitorsScroll)
	for i, row in ipairs(compRows) do
		local index = offset + i
		local data = list[index]
		row.data = data
		if data and index <= numRecords then
			local unitPrice = data.buyoutPrice / math.max(1, data.stackSize or 1)
			row.priceText:SetText(money(unitPrice))
			row.stacksText:SetText(string.format("%d × %d", data.count or 1, data.stackSize or 1))

			local seller = data.owner or "Unknown"
			if data.yours then
				seller = "|cff55dd55" .. Z("yours") .. "|r"
			end
			row.sellerText:SetText(seller)
			row:Show()
		else
			row:Hide()
			row.data = nil
		end
	end
end

-- ============================================================================
-- Post Execution
-- ============================================================================
local function PostStagedAuction()
	if InCombatLockdown and InCombatLockdown() then
		if Atr_Error_Display then
			Atr_Error_Display(Z("Cannot post auctions during combat."))
		end
		return
	end

	if not stagedItem then
		return
	end

	local size = math.max(1, GetStagedStackSize())
	local count = math.max(1, GetStagedNumStacks())
	local unitBuyout = GetInputBuyout()
	local unitBid = GetInputBid()
	if priceMode == "stack" then
		unitBuyout = math.floor(unitBuyout / size)
		unitBid = math.floor(unitBid / size)
	end

	local stackBuyout = unitBuyout * size
	local stackBid = unitBid * size

	-- Two-way synchronization with legacy Auctionator controls
	if Atr_StackPrice then
		MoneyInputFrame_SetCopper(Atr_StackPrice, stackBuyout)
	end
	if Atr_StartingPrice then
		MoneyInputFrame_SetCopper(Atr_StartingPrice, stackBid)
	end
	if Atr_ItemPrice then
		MoneyInputFrame_SetCopper(Atr_ItemPrice, unitBuyout)
	end
	if Atr_Batch_Stacksize then
		Atr_Batch_Stacksize:SetText(size)
	end
	if Atr_Batch_NumAuctions then
		Atr_Batch_NumAuctions:SetText(count)
	end
	if Atr_Duration and UIDropDownMenu_SetSelectedValue then
		UIDropDownMenu_SetSelectedValue(Atr_Duration, selectedDuration)
	end
	if AuctionFrameAuctions then
		AuctionFrameAuctions.duration = selectedDuration
	end

	-- Execute via verified safety pipeline
	if Atr_CreateAuction_OnClick then
		Atr_CreateAuction_OnClick()
	end
end

-- ============================================================================
-- UI Panel Construction
-- ============================================================================
local function MakeSellTerminal()
	panel = CreateFrame("Frame", "Atr_SellTerminalPanel", AuctionFrame)
	panel:SetFrameLevel(AuctionFrame:GetFrameLevel() + 30)
	Atr_AnalysisFit(panel)
	panel:SetBackdrop(nil)

	-- ------------------------------------------------------------------------
	-- Column 1: Bag Inventory Sidebar
	-- ------------------------------------------------------------------------
	panel.bagSidebar = CreateFrame("Frame", "Atr_SellBagSidebar", panel)
	panel.bagSidebar:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -36)
	panel.bagSidebar:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 30)
	panel.bagSidebar:SetWidth(235)
	Atr_AnalysisBackdrop(panel.bagSidebar, 1, "sidebar")

	-- Search Box
	searchBox = CreateFrame("EditBox", "Atr_SellBagSearch", panel.bagSidebar, "InputBoxTemplate")
	Atr_AnalysisSkin(searchBox, "EditBox")
	searchBox:SetPoint("TOPLEFT", panel.bagSidebar, "TOPLEFT", 10, -8)
	searchBox:SetPoint("TOPRIGHT", panel.bagSidebar, "TOPRIGHT", -28, -8)
	searchBox:SetHeight(20)
	searchBox:SetAutoFocus(false)
	searchBox:SetScript("OnTextChanged", function()
		Atr_FilterBagItems()
	end)

	clearSearchBtn = CreateFrame("Button", nil, panel.bagSidebar, "UIPanelButtonTemplate")
	Atr_AnalysisSkin(clearSearchBtn, "Button")
	clearSearchBtn:SetPoint("LEFT", searchBox, "RIGHT", 4, 0)
	clearSearchBtn:SetSize(18, 18)
	clearSearchBtn:SetText("x")
	clearSearchBtn:SetScript("OnClick", function()
		searchBox:SetText("")
		searchBox:ClearFocus()
	end)

	-- Category Filter Pills: [Все] [Реагенты] [Шмот] [Расходники]
	local cats = {
		{ id = "ALL", label = Z("All"), width = 48 },
		{ id = "TRADE", label = Z("Trade Goods"), width = 58 },
		{ id = "EQUIP", label = Z("Equipment"), width = 48 },
		{ id = "CONSUMABLE", label = Z("Consumables"), width = 56 },
	}
	local prevCat = nil
	for _, cat in ipairs(cats) do
		local btn = CreateFrame("Button", nil, panel.bagSidebar, "UIPanelButtonTemplate")
		Atr_AnalysisSkin(btn, "Button")
		btn:SetSize(cat.width, 20)
		if not prevCat then
			btn:SetPoint("TOPLEFT", panel.bagSidebar, "TOPLEFT", 8, -32)
		else
			btn:SetPoint("LEFT", prevCat, "RIGHT", 3, 0)
		end
		btn:SetText(cat.label)
		btn:SetScript("OnClick", function()
			selectedCategory = cat.id
			Atr_FilterBagItems()
		end)
		categoryButtons[#categoryButtons + 1] = btn
		prevCat = btn
	end

	-- Bag ScrollFrame
	bagScroll = CreateFrame("ScrollFrame", "Atr_SellBagScroll", panel.bagSidebar, "FauxScrollFrameTemplate")
	bagScroll:SetPoint("TOPLEFT", panel.bagSidebar, "TOPLEFT", 0, -56)
	bagScroll:SetPoint("BOTTOMRIGHT", panel.bagSidebar, "BOTTOMRIGHT", -22, 6)
	bagScroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, 33, Atr_RenderBagInventory)
	end)

	-- Bag Rows (10 rows)
	for i = 1, 10 do
		local row = CreateFrame("Button", "Atr_SellBagRow" .. i, panel.bagSidebar)
		row:SetHeight(33)
		row:SetPoint("LEFT", panel.bagSidebar, "LEFT", 4, 0)
		row:SetPoint("RIGHT", panel.bagSidebar, "RIGHT", -24, 0)
		row:SetPoint("TOP", panel.bagSidebar, "TOP", 0, -56 - (i - 1) * 33)

		local highlight = row:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
		highlight:SetBlendMode("ADD")

		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(26, 26)
		row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)

		row.countText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
		row.countText:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 1, 0)

		row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		row.nameText:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
		row.nameText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -1)
		row.nameText:SetJustifyH("LEFT")

		row.priceText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		row.priceText:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 2)
		row.priceText:SetJustifyH("LEFT")

		row.valueText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.valueText:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 2)
		row.valueText:SetJustifyH("RIGHT")

		row:SetScript("OnEnter", function(self)
			if self.data and self.data.slots and #self.data.slots > 0 then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				local first = self.data.slots[1]
				GameTooltip:SetBagItem(first.bag, first.slot)
				GameTooltip:Show()
			end
		end)
		row:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		row:SetScript("OnClick", function(self)
			if self.data then
				StageBagItem(self.data)
			end
		end)

		bagRows[i] = row
	end

	-- ------------------------------------------------------------------------
	-- Column 2: Staging & Posting Controls
	-- ------------------------------------------------------------------------
	panel.staging = CreateFrame("Frame", "Atr_SellStagingPanel", panel)
	panel.staging:SetPoint("TOPLEFT", panel.bagSidebar, "TOPRIGHT", 8, 0)
	panel.staging:SetPoint("BOTTOMLEFT", panel.bagSidebar, "BOTTOMRIGHT", 8, 0)
	panel.staging:SetWidth(290)
	Atr_AnalysisBackdrop(panel.staging, 1, "body")

	-- Header: Icon + Name + Counts
	stagedIcon = panel.staging:CreateTexture(nil, "ARTWORK")
	stagedIcon:SetSize(40, 40)
	stagedIcon:SetPoint("TOPLEFT", panel.staging, "TOPLEFT", 12, -10)
	stagedIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

	stagedName = panel.staging:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	stagedName:SetPoint("TOPLEFT", stagedIcon, "TOPRIGHT", 10, -2)
	stagedName:SetPoint("TOPRIGHT", panel.staging, "TOPRIGHT", -10, -2)
	stagedName:SetJustifyH("LEFT")
	stagedName:SetText("|cff888888" .. Z("No item selected") .. "|r")

	stagedCounts = panel.staging:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	stagedCounts:SetPoint("TOPLEFT", stagedIcon, "TOPRIGHT", 10, -22)
	stagedCounts:SetPoint("TOPRIGHT", panel.staging, "TOPRIGHT", -10, -22)
	stagedCounts:SetJustifyH("LEFT")
	stagedCounts:SetText(Z("Select an item from your bags or drop it here"))

	-- Reference Pricing Cards Container
	local refContainer = CreateFrame("Frame", nil, panel.staging)
	refContainer:SetPoint("TOPLEFT", panel.staging, "TOPLEFT", 10, -56)
	panel.refContainer = refContainer
	refContainer:SetPoint("TOPRIGHT", panel.staging, "TOPRIGHT", -10, -56)
	refContainer:SetHeight(44)
	Atr_AnalysisBackdrop(refContainer, 0.7, "heading")

	local function MakeRefCard(title, xOffset)
		local t = refContainer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		t:SetPoint("TOPLEFT", refContainer, "TOPLEFT", xOffset, -4)
		t:SetText(title)
		local v = refContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		v:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -3)
		v:SetText("--")
		return v
	end
	refLowVal = MakeRefCard(Z("Lowest Buyout"), 8)
	refMarketVal = MakeRefCard(Z("Market Median"), 100)
	refVendorVal = MakeRefCard(Z("Vendor Floor"), 192)

	-- Quick Price Buttons
	local quickPrices = {
		{ label = Z("Undercut 1c"), mode = "undercut", width = 86 },
		{ label = Z("Match"), mode = "match", width = 86 },
		{ label = Z("Market"), mode = "market", width = 86 },
	}
	local prevPriceBtn = nil
	for _, q in ipairs(quickPrices) do
		local b = CreateFrame("Button", nil, panel.staging, "UIPanelButtonTemplate")
		Atr_AnalysisSkin(b, "Button")
		b:SetSize(q.width, 22)
		if not prevPriceBtn then
			b:SetPoint("TOPLEFT", refContainer, "BOTTOMLEFT", 0, -6)
		else
			b:SetPoint("LEFT", prevPriceBtn, "RIGHT", 5, 0)
		end
		b:SetText(q.label)
		b:SetScript("OnClick", function()
			ApplyQuickPrice(q.mode)
		end)
		prevPriceBtn = b
	end

	-- Buyout Input Fields
	local buyoutLabel = panel.staging:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	buyoutLabel:SetPoint("TOPLEFT", prevPriceBtn, "BOTTOMLEFT", 0, -8)
	buyoutLabel:SetText(Z("Buyout Price") .. " (" .. Z("Per Item") .. "):")

	buyoutGold = CreateFrame("EditBox", "Atr_SellBuyoutGold", panel.staging, "InputBoxTemplate")
	buyoutSilver = CreateFrame("EditBox", "Atr_SellBuyoutSilver", panel.staging, "InputBoxTemplate")
	buyoutCopper = CreateFrame("EditBox", "Atr_SellBuyoutCopper", panel.staging, "InputBoxTemplate")

	local function SetupMoneyBox(eb, prev, w)
		Atr_AnalysisSkin(eb, "EditBox")
		eb:SetNumeric(true)
		eb:SetAutoFocus(false)
		eb:SetSize(w, 20)
		if prev then
			eb:SetPoint("LEFT", prev, "RIGHT", 14, 0)
		else
			eb:SetPoint("TOPLEFT", buyoutLabel, "BOTTOMLEFT", 0, -4)
		end
		eb:SetScript("OnTextChanged", RecalculateEstimates)
	end
	SetupMoneyBox(buyoutGold, nil, 60)
	SetupMoneyBox(buyoutSilver, buyoutGold, 38)
	SetupMoneyBox(buyoutCopper, buyoutSilver, 38)

	local function AddCoinIcon(eb, file)
		local icon = panel.staging:CreateTexture(nil, "ARTWORK")
		icon:SetSize(14, 14)
		icon:SetPoint("LEFT", eb, "RIGHT", 2, 0)
		icon:SetTexture(file)
	end
	AddCoinIcon(buyoutGold, "Interface\\MoneyFrame\\UI-GoldIcon")
	AddCoinIcon(buyoutSilver, "Interface\\MoneyFrame\\UI-SilverIcon")
	AddCoinIcon(buyoutCopper, "Interface\\MoneyFrame\\UI-CopperIcon")

	-- Bid Input Fields
	local bidLabel = panel.staging:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	bidLabel:SetPoint("TOPLEFT", buyoutGold, "BOTTOMLEFT", 0, -8)
	bidLabel:SetText(Z("Starting Bid") .. ":")

	bidGold = CreateFrame("EditBox", "Atr_SellBidGold", panel.staging, "InputBoxTemplate")
	bidSilver = CreateFrame("EditBox", "Atr_SellBidSilver", panel.staging, "InputBoxTemplate")
	bidCopper = CreateFrame("EditBox", "Atr_SellBidCopper", panel.staging, "InputBoxTemplate")

	Atr_AnalysisSkin(bidGold, "EditBox")
	bidGold:SetNumeric(true)
	bidGold:SetAutoFocus(false)
	bidGold:SetSize(60, 20)
	bidGold:SetPoint("TOPLEFT", bidLabel, "BOTTOMLEFT", 0, -4)

	Atr_AnalysisSkin(bidSilver, "EditBox")
	bidSilver:SetNumeric(true)
	bidSilver:SetAutoFocus(false)
	bidSilver:SetSize(38, 20)
	bidSilver:SetPoint("LEFT", bidGold, "RIGHT", 14, 0)

	Atr_AnalysisSkin(bidCopper, "EditBox")
	bidCopper:SetNumeric(true)
	bidCopper:SetAutoFocus(false)
	bidCopper:SetSize(38, 20)
	bidCopper:SetPoint("LEFT", bidSilver, "RIGHT", 14, 0)

	AddCoinIcon(bidGold, "Interface\\MoneyFrame\\UI-GoldIcon")
	AddCoinIcon(bidSilver, "Interface\\MoneyFrame\\UI-SilverIcon")
	AddCoinIcon(bidCopper, "Interface\\MoneyFrame\\UI-CopperIcon")

	-- Quick Stacking Buttons
	local quickStacks = {
		{ label = Z("All"), mode = "all", width = 86 },
		{ label = Z("Singles"), mode = "singles", width = 86 },
		{ label = Z("Full Stacks"), mode = "full", width = 86 },
	}
	local prevStackBtn = nil
	for _, q in ipairs(quickStacks) do
		local b = CreateFrame("Button", nil, panel.staging, "UIPanelButtonTemplate")
		Atr_AnalysisSkin(b, "Button")
		b:SetSize(q.width, 22)
		if not prevStackBtn then
			b:SetPoint("TOPLEFT", bidGold, "BOTTOMLEFT", 0, -10)
		else
			b:SetPoint("LEFT", prevStackBtn, "RIGHT", 5, 0)
		end
		b:SetText(q.label)
		b:SetScript("OnClick", function()
			ApplyQuickStacking(q.mode)
		end)
		prevStackBtn = b
	end

	-- Stacking EditBoxes
	local stacksLabel = panel.staging:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	stacksLabel:SetPoint("TOPLEFT", prevStackBtn, "BOTTOMLEFT", 0, -8)
	stacksLabel:SetText(Z("Stacks:") .. " × " .. Z("Stack Size:"))

	numStacksEdit = CreateFrame("EditBox", "Atr_SellNumStacks", panel.staging, "InputBoxTemplate")
	Atr_AnalysisSkin(numStacksEdit, "EditBox")
	numStacksEdit:SetNumeric(true)
	numStacksEdit:SetAutoFocus(false)
	numStacksEdit:SetSize(50, 20)
	numStacksEdit:SetPoint("TOPLEFT", stacksLabel, "BOTTOMLEFT", 0, -4)
	numStacksEdit:SetScript("OnTextChanged", RecalculateEstimates)

	local multSign = panel.staging:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	multSign:SetPoint("LEFT", numStacksEdit, "RIGHT", 6, 0)
	multSign:SetText("×")

	stackSizeEdit = CreateFrame("EditBox", "Atr_SellStackSize", panel.staging, "InputBoxTemplate")
	Atr_AnalysisSkin(stackSizeEdit, "EditBox")
	stackSizeEdit:SetNumeric(true)
	stackSizeEdit:SetAutoFocus(false)
	stackSizeEdit:SetSize(50, 20)
	stackSizeEdit:SetPoint("LEFT", multSign, "RIGHT", 6, 0)
	stackSizeEdit:SetScript("OnTextChanged", RecalculateEstimates)

	-- Duration Buttons
	local durations = {
		{ id = 1, label = Z("12 Hours"), width = 86 },
		{ id = 2, label = Z("24 Hours"), width = 86 },
		{ id = 3, label = Z("48 Hours"), width = 86 },
	}
	local prevDur = nil
	for _, d in ipairs(durations) do
		local b = CreateFrame("Button", nil, panel.staging, "UIPanelButtonTemplate")
		Atr_AnalysisSkin(b, "Button")
		b:SetSize(d.width, 20)
		if not prevDur then
			b:SetPoint("TOPLEFT", numStacksEdit, "BOTTOMLEFT", 0, -8)
		else
			b:SetPoint("LEFT", prevDur, "RIGHT", 5, 0)
		end
		b:SetText(d.label)
		b:SetScript("OnClick", function()
			selectedDuration = d.id
			RecalculateEstimates()
		end)
		durationButtons[#durationButtons + 1] = b
		prevDur = b
	end

	-- Financial Estimates Footer
	local estLabel1 = panel.staging:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	estLabel1:SetPoint("TOPLEFT", prevDur, "BOTTOMLEFT", 0, -8)
	estLabel1:SetText(Z("Deposit:") .. " ")
	depositVal = panel.staging:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	depositVal:SetPoint("LEFT", estLabel1, "RIGHT", 2, 0)
	depositVal:SetText("--")

	local estLabel2 = panel.staging:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	estLabel2:SetPoint("LEFT", depositVal, "RIGHT", 14, 0)
	estLabel2:SetText(Z("Est. Net Revenue:") .. " ")
	netRevenueVal = panel.staging:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	netRevenueVal:SetPoint("LEFT", estLabel2, "RIGHT", 2, 0)
	netRevenueVal:SetText("--")

	-- Big Post Button
	postBtn = CreateFrame("Button", "Atr_SellPostButton", panel.staging, "UIPanelButtonTemplate")
	Atr_AnalysisSkin(postBtn, "Button")
	postBtn:SetSize(266, 32)
	postBtn:SetPoint("BOTTOM", panel.staging, "BOTTOM", 0, 8)
	postBtn:SetText(Z("Create Auction"))
	postBtn:SetScript("OnClick", PostStagedAuction)

	-- ------------------------------------------------------------------------
	-- Column 3: Live Market Competitors
	-- ------------------------------------------------------------------------
	panel.competitors = CreateFrame("Frame", "Atr_SellCompetitorsPanel", panel)
	panel.competitors:SetPoint("TOPLEFT", panel.staging, "TOPRIGHT", 8, 0)
	panel.competitors:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 30)
	Atr_AnalysisBackdrop(panel.competitors, 1, "body")

	compHeaderTitle = panel.competitors:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	compHeaderTitle:SetPoint("TOPLEFT", panel.competitors, "TOPLEFT", 10, -10)
	compHeaderTitle:SetText(Z("Market Competitors"))

	compStatusBadge = panel.competitors:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	compStatusBadge:SetPoint("TOPLEFT", compHeaderTitle, "BOTTOMLEFT", 0, -4)
	compStatusBadge:SetText("|cff55aaff● " .. Z("No Competitors") .. "|r")

	local rescanBtn = CreateFrame("Button", nil, panel.competitors, "UIPanelButtonTemplate")
	Atr_AnalysisSkin(rescanBtn, "Button")
	rescanBtn:SetSize(72, 20)
	rescanBtn:SetPoint("TOPRIGHT", panel.competitors, "TOPRIGHT", -10, -8)
	rescanBtn:SetText(Z("Refresh"))
	rescanBtn:SetScript("OnClick", function()
		if stagedItem and gSellPane then
			gSellPane:DoSearch(stagedItem.name, stagedItem.key, stagedItem.link, 20)
		end
	end)

	-- Table Header
	local thPrice = panel.competitors:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	thPrice:SetPoint("TOPLEFT", panel.competitors, "TOPLEFT", 10, -42)
	thPrice:SetText(Z("Unit Price"))

	local thStacks = panel.competitors:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	thStacks:SetPoint("LEFT", thPrice, "LEFT", 110, 0)
	thStacks:SetText(Z("Stacks:"))

	local thSeller = panel.competitors:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	thSeller:SetPoint("LEFT", thStacks, "LEFT", 70, 0)
	thSeller:SetText(Z("Seller"))

	-- Competitor ScrollFrame
	competitorsScroll =
		CreateFrame("ScrollFrame", "Atr_SellCompetitorsScroll", panel.competitors, "FauxScrollFrameTemplate")
	competitorsScroll:SetPoint("TOPLEFT", panel.competitors, "TOPLEFT", 0, -58)
	competitorsScroll:SetPoint("BOTTOMRIGHT", panel.competitors, "BOTTOMRIGHT", -22, 6)
	competitorsScroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, 26, Atr_RenderCompetitors)
	end)

	-- Competitor Rows (11 rows)
	for i = 1, 11 do
		local row = CreateFrame("Button", "Atr_SellCompRow" .. i, panel.competitors)
		row:SetHeight(26)
		row:SetPoint("LEFT", panel.competitors, "LEFT", 4, 0)
		row:SetPoint("RIGHT", panel.competitors, "RIGHT", -24, 0)
		row:SetPoint("TOP", panel.competitors, "TOP", 0, -58 - (i - 1) * 26)

		local highlight = row:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
		highlight:SetBlendMode("ADD")

		row.priceText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.priceText:SetPoint("LEFT", row, "LEFT", 6, 0)
		row.priceText:SetWidth(104)
		row.priceText:SetJustifyH("LEFT")

		row.stacksText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		row.stacksText:SetPoint("LEFT", row.priceText, "RIGHT", 4, 0)
		row.stacksText:SetWidth(66)
		row.stacksText:SetJustifyH("LEFT")

		row.sellerText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.sellerText:SetPoint("LEFT", row.stacksText, "RIGHT", 4, 0)
		row.sellerText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
		row.sellerText:SetJustifyH("LEFT")

		row:SetScript("OnClick", function(self)
			if self.data and self.data.buyoutPrice and self.data.buyoutPrice > 0 then
				local unitPrice = self.data.buyoutPrice / math.max(1, self.data.stackSize or 1)
				SetInputBuyout(unitPrice)
				local startBid = (Atr_CalcStartPrice and Atr_CalcStartPrice(unitPrice)) or math.floor(unitPrice * 0.95)
				SetInputBid(startBid)
				RecalculateEstimates()
			end
		end)
		row:SetScript("OnEnter", function(self)
			if self.data then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:AddLine(Z("Click to match price"), 1, 0.82, 0)
				GameTooltip:AddDoubleLine(Z("Buyout Price"), money(self.data.buyoutPrice or 0), 1, 1, 1)
				GameTooltip:Show()
			end
		end)
		row:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)

		compRows[i] = row
	end

	-- ------------------------------------------------------------------------
	-- Panel Scripts & Lifecycle
	-- ------------------------------------------------------------------------
	panel:SetScript("OnShow", function(self)
		Atr_AnalysisFit(self)
		artwork = Atr_AnalysisBegin(self)
		if Atr_StyleAnalysisScroll then
			Atr_StyleAnalysisScroll(bagScroll, panel.bagSidebar)
			Atr_StyleAnalysisScroll(competitorsScroll, panel.competitors)
		end
		ScanPlayerBags()
		UpdateStagedDisplay()
	end)

	panel:SetScript("OnHide", function()
		Atr_AnalysisEnd(artwork)
		artwork = {}
		if searchBox then
			searchBox:ClearFocus()
		end
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)

	panel:SetScript("OnUpdate", function(_, elapsed)
		if bagScanDirty then
			bagScanThrottle = bagScanThrottle + elapsed
			if bagScanThrottle >= 0.25 then
				bagScanDirty = false
				bagScanThrottle = 0
				ScanPlayerBags()
			end
		end
	end)

	panel:RegisterEvent("BAG_UPDATE")
	panel:SetScript("OnEvent", function(self, event)
		if event == "BAG_UPDATE" and self:IsShown() then
			bagScanDirty = true
		end
	end)

	panel:Hide()
end

-- ============================================================================
-- Integration & Hooks
-- ============================================================================
function Atr_UpdateSellTabVisibility()
	if not AuctionFrame or not AuctionFrame:IsShown() then
		return
	end

	local useModern = (AUCTIONATOR_SAVEDVARS and AUCTIONATOR_SAVEDVARS.modernSell ~= false)
	local isSellTab = (Atr_IsTabSelected and Atr_IsTabSelected(1)) -- SELL_TAB is 1

	if isSellTab and useModern then
		if Atr_Main_Panel and Atr_Main_Panel:IsShown() then
			Atr_Main_Panel:Hide()
		end
		if panel and not panel:IsShown() then
			panel:Show()
		end
	else
		if panel and panel:IsShown() then
			panel:Hide()
		end
		if isSellTab and not useModern and Atr_Main_Panel and not Atr_Main_Panel:IsShown() then
			Atr_Main_Panel:Show()
		end
	end
end

AuctionatorRemastered.Legacy.Hook("Atr_AuctionFrameTab_OnClick", function()
	Atr_UpdateSellTabVisibility()
end)

AuctionatorRemastered.Legacy.Hook("Atr_ShowCurrentAuctions", function()
	if panel and panel:IsShown() then
		UpdateStagedPricingCards()
		Atr_RenderCompetitors()
	end
end)

AuctionatorRemastered.Legacy.Hook("Atr_ClearList", function()
	if panel and panel:IsShown() then
		Atr_RenderCompetitors()
	end
end)

AuctionatorRemastered.Legacy.Hook("Atr_Init", function()
	MakeSellTerminal()
end)
