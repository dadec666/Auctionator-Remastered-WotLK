-- BuyTerminal.lua: Modern 3-Column Buy Terminal for Auctionator Remastered (WoW 3.3.5a)
-- Integrated 3-column layout expanding AuctionFrame:
-- Column 1: Search Sidebar & Shopping Lists (Search bar, category filters, Recent searches / Shopping Lists toggle, item list)
-- Column 2: Staging & Checkout Terminal (Item header, iLvl, Req level, Reference pricing cards, Quick quantity presets, Cart summary, Big Buy button)
-- Column 3: Live Market Depth & Competitors (All active market listings, Stacks, Seller, Discount badge, Click-to-select, Refresh button)

local panel, listScroll, depthScroll
local searchBox, clearSearchBtn
local stagedIcon, stagedName, stagedDetails, stagedAvailable
local refLowVal, refMarketVal, refDiscountVal
local numItemsEdit, numStacksEdit
local unitPriceVal, totalCostVal, playerBalanceVal, balanceStatus
local buyBtn
local depthHeaderTitle, depthStatusBadge
local categoryButtons = {}
local artwork = {}

local sidebarMode = "RECENTS" -- "RECENTS" or "LISTS"
local selectedCategory = "ALL"
local sidebarItems = {}
local filteredSidebarItems = {}
local sidebarRows = {}
local depthRows = {}

local stagedItem = nil
local selectedListing = nil
local isBuyingInProgress = false

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
-- Level Requirement Coloring (Req Color Logic from aux)
-- ============================================================================
local function GetReqLevelColor(reqLevel)
	if not reqLevel or reqLevel <= 0 then
		return 0.8, 0.8, 0.8
	end
	local playerLevel = UnitLevel and UnitLevel("player") or 80
	local diff = reqLevel - playerLevel
	if diff >= 5 then
		return 1.0, 0.2, 0.2 -- Red: 5+ levels above
	elseif diff >= 3 then
		return 1.0, 0.5, 0.0 -- Orange: 3-4 levels above
	elseif diff >= 1 then
		return 1.0, 0.8, 0.0 -- Yellow: 1-2 levels above
	elseif diff <= -10 then
		return 0.5, 0.5, 0.5 -- Gray: trivial low level
	else
		return 0.2, 1.0, 0.2 -- Green: usable right now
	end
end

-- ============================================================================
-- Column 1: Sidebar Data Loading (Recents & Shopping Lists)
-- ============================================================================
local function LoadSidebarItems()
	sidebarItems = {}

	if sidebarMode == "RECENTS" then
		local recentsList = AUCTIONATOR_SHOPPING_LISTS and AUCTIONATOR_SHOPPING_LISTS[1]
		if recentsList and recentsList.items then
			for _, itemName in ipairs(recentsList.items) do
				local link = nil
				local texture = "Interface\\Icons\\INV_Misc_QuestionMark"
				local quality = 1
				local itemType = ""
				local ilvl = 0
				local reqLvl = 0

				local name, itemLink, itemRarity, itemLevel, minLevel, itemTypeStr, _, _, _, itemTexture =
					GetItemInfo(itemName)
				if name then
					link = itemLink
					texture = itemTexture or texture
					quality = itemRarity or quality
					itemType = itemTypeStr or ""
					ilvl = itemLevel or 0
					reqLvl = minLevel or 0
				end

				local lastPrice = (Atr_GetAuctionPrice and Atr_GetAuctionPrice(itemName))
					or (Atr_MarketReference and Atr_MarketReference(itemName))
					or 0

				sidebarItems[#sidebarItems + 1] = {
					name = name or itemName,
					link = link,
					texture = texture,
					quality = quality,
					type = itemType,
					ilvl = ilvl,
					reqLevel = reqLvl,
					price = lastPrice,
				}
			end
		end
	elseif sidebarMode == "LISTS" then
		-- Load items from all user-created shopping lists
		if AUCTIONATOR_SHOPPING_LISTS then
			for idx = 2, #AUCTIONATOR_SHOPPING_LISTS do
				local slist = AUCTIONATOR_SHOPPING_LISTS[idx]
				if slist and slist.items then
					for _, itemName in ipairs(slist.items) do
						local name, itemLink, itemRarity, itemLevel, minLevel, itemTypeStr, _, _, _, itemTexture =
							GetItemInfo(itemName)
						local lastPrice = (Atr_GetAuctionPrice and Atr_GetAuctionPrice(itemName))
							or (Atr_MarketReference and Atr_MarketReference(itemName))
							or 0
						sidebarItems[#sidebarItems + 1] = {
							name = name or itemName,
							listName = slist.name,
							link = itemLink,
							texture = itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark",
							quality = itemRarity or 1,
							type = itemTypeStr or "",
							ilvl = itemLevel or 0,
							reqLevel = minLevel or 0,
							price = lastPrice,
						}
					end
				end
			end
		end
	end

	Atr_FilterBuySidebar()
end

function Atr_FilterBuySidebar()
	filteredSidebarItems = {}
	local search = searchBox and searchBox:GetText() or ""
	local parsed = Atr_ParseSearchModifiers and Atr_ParseSearchModifiers(search)
	local query = parsed and parsed.cleanSearchText or search
	query = string.lower(string.trim and string.trim(query) or query)

	for _, item in ipairs(sidebarItems) do
		local matchesCategory = true
		if selectedCategory == "TRADE" then
			matchesCategory = (item.type == "Trade Goods" or item.type == "Gem" or item.type == "Recipe")
		elseif selectedCategory == "EQUIP" then
			matchesCategory = (item.type == "Armor" or item.type == "Weapon")
		elseif selectedCategory == "CONSUMABLE" then
			matchesCategory = (item.type == "Consumable")
		end

		local matchesSearch = true
		if query ~= "" then
			if parsed and parsed.exact then
				matchesSearch = (string.lower(item.name) == query)
			else
				matchesSearch = string.find(string.lower(item.name), query, 1, true) ~= nil
			end
		end

		if parsed and parsed.quality and item.quality and item.quality ~= parsed.quality then
			matchesSearch = false
		end
		if parsed and parsed.minItemLevel and item.ilvl and item.ilvl < parsed.minItemLevel then
			matchesSearch = false
		end
		if parsed and parsed.maxItemLevel and item.ilvl and item.ilvl > parsed.maxItemLevel then
			matchesSearch = false
		end

		if matchesCategory and matchesSearch then
			filteredSidebarItems[#filteredSidebarItems + 1] = item
		end
	end

	Atr_RenderBuySidebar()
end

function Atr_RenderBuySidebar()
	if not listScroll then
		return
	end

	local numRecords = #filteredSidebarItems
	local visibleRows = #sidebarRows
	FauxScrollFrame_Update(listScroll, numRecords, visibleRows, 33)

	local offset = FauxScrollFrame_GetOffset(listScroll)
	for i, row in ipairs(sidebarRows) do
		local index = offset + i
		local data = filteredSidebarItems[index]
		row.data = data
		if data and index <= numRecords then
			row.icon:SetTexture(data.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
			local r, g, b = GetItemQualityColor(data.quality or 1)
			row.nameText:SetText(data.name)
			row.nameText:SetTextColor(r or 1, g or 1, b or 1)

			if data.price > 0 then
				row.priceText:SetText(money(data.price))
			else
				row.priceText:SetText("|cff888888--|r")
			end
			row:Show()
		else
			row:Hide()
			row.data = nil
		end
	end
end

-- ============================================================================
-- Search Trigger
-- ============================================================================
local function TriggerBuySearch(text)
	if not text or string.trim(text) == "" then
		return
	end
	text = string.trim(text)

	if searchBox then
		searchBox:SetText(text)
		searchBox:ClearFocus()
	end

	-- Add to Recents list
	if Atr_AddToRecents then
		Atr_AddToRecents(text)
	end

	-- Execute query via gShopPane
	if gShopPane then
		if Atr_ClearAll then
			Atr_ClearAll()
		end
		gShopPane:DoSearch(text)
	end

	-- Reload sidebar recents
	LoadSidebarItems()
end

function Atr_TriggerBuySearch(text)
	TriggerBuySearch(text)
end

-- ============================================================================
-- Column 2: Staging & Checkout Logic
-- ============================================================================
local function GetSelectedQuantity()
	local numItems = numItemsEdit and numItemsEdit:GetNumber() or 1
	return math.max(1, numItems)
end

local function RecalculateCart()
	if not stagedItem or not selectedListing then
		if unitPriceVal then
			unitPriceVal:SetText("--")
		end
		if totalCostVal then
			totalCostVal:SetText("--")
		end
		if playerBalanceVal then
			playerBalanceVal:SetText(money((GetMoney and GetMoney()) or 0))
		end
		if balanceStatus then
			balanceStatus:SetText("")
		end
		if buyBtn then
			buyBtn:Disable()
			buyBtn:SetText(Z("Create Auction") and Z("Buy") or "Buy")
		end
		return
	end

	if selectedListing.yours then
		if unitPriceVal then
			unitPriceVal:SetText(money(selectedListing.unitPrice or math.floor(selectedListing.buyoutPrice / selectedListing.stackSize)))
		end
		if totalCostVal then
			totalCostVal:SetText("--")
		end
		if balanceStatus then
			balanceStatus:SetText("|cffffcc00" .. Z("Your own auction") .. "|r")
		end
		if buyBtn then
			buyBtn:Disable()
			buyBtn:SetText(Z("Own Auction"))
		end
		return
	end

	local unitPrice = selectedListing.unitPrice or math.floor(selectedListing.buyoutPrice / selectedListing.stackSize)
	local numToBuy = GetSelectedQuantity()
	local totalCost = unitPrice * numToBuy

	if unitPriceVal then
		unitPriceVal:SetText(money(unitPrice))
	end
	if totalCostVal then
		totalCostVal:SetText(money(totalCost))
	end

	local myMoney = (GetMoney and GetMoney()) or 0
	if playerBalanceVal then
		playerBalanceVal:SetText(money(myMoney))
	end

	if myMoney < totalCost then
		if balanceStatus then
			balanceStatus:SetText("|cffff5555" .. Z("Not enough gold") .. "|r")
		end
		if buyBtn then
			buyBtn:Disable()
		end
	else
		local balanceAfter = myMoney - totalCost
		if balanceStatus then
			balanceStatus:SetText("|cff55dd55" .. Z("Balance after:") .. " " .. money(balanceAfter) .. "|r")
		end
		if buyBtn and not isBuyingInProgress then
			buyBtn:Enable()
			buyBtn:SetText(string.format(Z("BUY %d FOR %s"), numToBuy, money(totalCost)))
		end
	end
end

local function UpdateStagedItemDisplay()
	if not stagedItem then
		if stagedIcon then
			stagedIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		end
		if stagedName then
			stagedName:SetText("|cff888888" .. Z("No item selected") .. "|r")
		end
		if stagedDetails then
			stagedDetails:SetText(Z("Select an item from the left sidebar to start buying"))
		end
		if stagedAvailable then
			stagedAvailable:SetText("")
		end
		if refLowVal then
			refLowVal:SetText("--")
		end
		if refMarketVal then
			refMarketVal:SetText("--")
		end
		if refDiscountVal then
			refDiscountVal:SetText("--")
		end
		if numItemsEdit then
			numItemsEdit:SetText("")
		end
		if numStacksEdit then
			numStacksEdit:SetText("")
		end
		RecalculateCart()
		Atr_RenderMarketDepth()
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

	-- Item Level and Requirement details
	local detailsText = ""
	if stagedItem.ilvl and stagedItem.ilvl > 1 then
		detailsText = detailsText .. "iLvl " .. stagedItem.ilvl .. "   "
	end
	if stagedItem.reqLevel and stagedItem.reqLevel > 1 then
		local rr, gg, bb = GetReqLevelColor(stagedItem.reqLevel)
		detailsText = detailsText
			.. string.format("|cff%02x%02x%02xReq %d|r   ", rr * 255, gg * 255, bb * 255, stagedItem.reqLevel)
	end
	if stagedItem.type and stagedItem.type ~= "" then
		detailsText = detailsText .. "|cff888888(" .. stagedItem.type .. ")|r"
	end
	if stagedDetails then
		stagedDetails:SetText(detailsText)
	end

	-- Market Reference & Analytics
	local lowestBuyout = nil
	local totalAvailable = 0
	local totalStacks = 0
	if gShopPane and gShopPane.activeScan and gShopPane.activeScan.sortedData then
		for _, entry in ipairs(gShopPane.activeScan.sortedData) do
			if entry.type == "n" and (entry.buyoutPrice or 0) > 0 then
				local uPrice = entry.buyoutPrice / math.max(1, entry.stackSize or 1)
				if not lowestBuyout or uPrice < lowestBuyout then
					lowestBuyout = uPrice
				end
				totalAvailable = totalAvailable + ((entry.count or 1) * (entry.stackSize or 1))
				totalStacks = totalStacks + (entry.count or 1)
			end
		end
	end

	if stagedAvailable then
		stagedAvailable:SetText(
			string.format(Z("Available on AH: %d"), totalAvailable) .. " (" .. totalStacks .. " " .. Z("Stacks:") .. ")"
		)
	end

	local marketRef = (Atr_MarketReference and Atr_MarketReference(stagedItem.name))
		or (Atr_GetAuctionPrice and Atr_GetAuctionPrice(stagedItem.name))
		or 0

	if refLowVal then
		refLowVal:SetText(lowestBuyout and money(lowestBuyout) or "|cff888888--|r")
	end
	if refMarketVal then
		refMarketVal:SetText(marketRef > 0 and money(marketRef) or "|cff888888--|r")
	end

	if refDiscountVal then
		if lowestBuyout and marketRef and marketRef > 0 then
			local pct = math.floor(((lowestBuyout - marketRef) / marketRef) * 100 + 0.5)
			if pct < 0 then
				refDiscountVal:SetText(string.format("|cff55dd55-%d%%|r", math.abs(pct)))
			elseif pct > 0 then
				refDiscountVal:SetText(string.format("|cffffaa55+%d%%|r", pct))
			else
				refDiscountVal:SetText("|cffffff550%|r")
			end
		else
			refDiscountVal:SetText("--")
		end
	end

	-- Auto-select the lowest price listing if not already selected
	if not selectedListing and gShopPane and gShopPane.activeScan and gShopPane.activeScan.sortedData then
		for _, entry in ipairs(gShopPane.activeScan.sortedData) do
			if entry.type == "n" and (entry.buyoutPrice or 0) > 0 then
				selectedListing = entry
				selectedListing.unitPrice = entry.buyoutPrice / math.max(1, entry.stackSize or 1)
				break
			end
		end
	end

	-- Set initial quantity
	if selectedListing then
		local initCount = selectedListing.stackSize or 1
		if numItemsEdit then
			numItemsEdit:SetText(initCount)
		end
		if numStacksEdit then
			numStacksEdit:SetText(1)
		end
	end

	RecalculateCart()
	Atr_RenderMarketDepth()
end

-- ============================================================================
-- Column 3: Live Market Depth & Listings
-- ============================================================================
function Atr_RenderMarketDepth()
	if not depthScroll then
		return
	end

	local listings = {}
	if gShopPane and gShopPane.activeScan and gShopPane.activeScan.sortedData then
		for _, entry in ipairs(gShopPane.activeScan.sortedData) do
			if entry.type == "n" and (entry.buyoutPrice or 0) > 0 then
				entry.unitPrice = entry.buyoutPrice / math.max(1, entry.stackSize or 1)
				listings[#listings + 1] = entry
			end
		end
	end

	if depthStatusBadge then
		if #listings > 0 then
			depthStatusBadge:SetText(string.format("|cff55dd55● %d лотов|r", #listings))
		else
			depthStatusBadge:SetText("|cff55aaff● " .. Z("No Competitors") .. "|r")
		end
	end

	local numRecords = #listings
	local visibleRows = #depthRows
	FauxScrollFrame_Update(depthScroll, numRecords, visibleRows, 26)

	local offset = FauxScrollFrame_GetOffset(depthScroll)
	for i, row in ipairs(depthRows) do
		local index = offset + i
		local data = listings[index]
		row.data = data
		if data and index <= numRecords then
			row.priceText:SetText(money(data.unitPrice))
			row.stacksText:SetText(string.format("%d × %d", data.count or 1, data.stackSize or 1))

			local seller = data.owner or "Unknown"
			if data.yours then
				seller = "|cff55dd55" .. Z("yours") .. "|r"
			end
			row.sellerText:SetText(seller)

			if selectedListing == data then
				row.selectedBg:Show()
			else
				row.selectedBg:Hide()
			end

			row:Show()
		else
			row:Hide()
			row.data = nil
		end
	end
end

-- ============================================================================
-- Safe Buy Execution (Race Condition Guard & In-Place Checkout)
-- ============================================================================
local function ExecutePurchase()
	if not stagedItem or not selectedListing then
		return
	end

	if selectedListing.yours then
		if Atr_Error_Display then
			Atr_Error_Display(Z("Cannot buy your own auction"))
		end
		return
	end

	local numToBuy = GetSelectedQuantity()
	local numStacks = math.max(1, math.floor(numToBuy / math.max(1, selectedListing.stackSize or 1)))
	local unitCost = selectedListing.unitPrice or math.floor((selectedListing.buyoutPrice or 0) / math.max(1, selectedListing.stackSize or 1))
	local totalCost = unitCost * numToBuy
	local myMoney = (GetMoney and GetMoney()) or 0

	if totalCost > myMoney then
		if Atr_Error_Display then
			Atr_Error_Display(Z("You do not have enough gold\n\nto make any more purchases."))
		end
		return
	end

	-- Setup legacy Auctionator buy engine
	if gShopPane then
		-- Find index of selected listing in sortedData
		for idx, entry in ipairs(gShopPane.activeScan.sortedData) do
			if entry == selectedListing then
				gShopPane.currIndex = idx
				break
			end
		end
	end

	-- Prepare purchase via verified AuctionatorBuy pipeline
	if Atr_Buy1_Onclick then
		Atr_Buy1_Onclick()

		-- Set desired number of stacks into Atr_Buy_Confirm_Numstacks
		if Atr_Buy_Confirm_Numstacks then
			Atr_Buy_Confirm_Numstacks:SetNumber(numStacks)
		end

		-- Hide the old classic popup dialog if modern buy is active!
		if Atr_Buy_Confirm_Frame and AUCTIONATOR_SAVEDVARS and AUCTIONATOR_SAVEDVARS.modernBuy ~= false then
			Atr_Buy_Confirm_Frame:Hide()
		end

		-- Confirm purchase directly
		if Atr_Buy_Confirm_OK then
			Atr_Buy_Confirm_OK()
		end
	end
end

-- ============================================================================
-- UI Panel Construction
-- ============================================================================
local function MakeBuyTerminal()
	panel = CreateFrame("Frame", "Atr_BuyTerminalPanel", AuctionFrame)
	panel:SetFrameLevel(AuctionFrame:GetFrameLevel() + 30)
	Atr_AnalysisFit(panel)
	panel:SetBackdrop(nil)

	-- ------------------------------------------------------------------------
	-- Column 1: Search Sidebar & Shopping Lists (~235px)
	-- ------------------------------------------------------------------------
	panel.sidebar = CreateFrame("Frame", "Atr_BuySidebar", panel)
	panel.sidebar:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -36)
	panel.sidebar:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 30)
	panel.sidebar:SetWidth(235)
	Atr_AnalysisBackdrop(panel.sidebar, 1, "sidebar")

	-- Search Input
	searchBox = CreateFrame("EditBox", "Atr_BuySearchBox", panel.sidebar, "InputBoxTemplate")
	Atr_AnalysisSkin(searchBox, "EditBox")
	searchBox:SetPoint("TOPLEFT", panel.sidebar, "TOPLEFT", 10, -8)
	searchBox:SetPoint("TOPRIGHT", panel.sidebar, "TOPRIGHT", -28, -8)
	searchBox:SetHeight(20)
	searchBox:SetAutoFocus(false)
	searchBox:SetScript("OnEnterPressed", function(self)
		TriggerBuySearch(self:GetText())
	end)
	searchBox:SetScript("OnTextChanged", function()
		Atr_FilterBuySidebar()
	end)

	clearSearchBtn = CreateFrame("Button", nil, panel.sidebar, "UIPanelButtonTemplate")
	Atr_AnalysisSkin(clearSearchBtn, "Button")
	clearSearchBtn:SetPoint("LEFT", searchBox, "RIGHT", 4, 0)
	clearSearchBtn:SetSize(18, 18)
	clearSearchBtn:SetText("x")
	clearSearchBtn:SetScript("OnClick", function()
		searchBox:SetText("")
		searchBox:ClearFocus()
		Atr_FilterBuySidebar()
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
		local btn = CreateFrame("Button", nil, panel.sidebar, "UIPanelButtonTemplate")
		Atr_AnalysisSkin(btn, "Button")
		btn:SetSize(cat.width, 20)
		if not prevCat then
			btn:SetPoint("TOPLEFT", panel.sidebar, "TOPLEFT", 8, -32)
		else
			btn:SetPoint("LEFT", prevCat, "RIGHT", 3, 0)
		end
		btn:SetText(cat.label)
		btn:SetScript("OnClick", function()
			selectedCategory = cat.id
			Atr_FilterBuySidebar()
		end)
		categoryButtons[#categoryButtons + 1] = btn
		prevCat = btn
	end

	-- Mode Selector: [Недавние] | [Списки]
	local btnRecents = CreateFrame("Button", nil, panel.sidebar, "UIPanelButtonTemplate")
	Atr_AnalysisSkin(btnRecents, "Button")
	btnRecents:SetSize(106, 20)
	btnRecents:SetPoint("TOPLEFT", panel.sidebar, "TOPLEFT", 8, -56)
	btnRecents:SetText(Z("Recent Searches"))

	local btnLists = CreateFrame("Button", nil, panel.sidebar, "UIPanelButtonTemplate")
	Atr_AnalysisSkin(btnLists, "Button")
	btnLists:SetSize(106, 20)
	btnLists:SetPoint("LEFT", btnRecents, "RIGHT", 5, 0)
	btnLists:SetText(Z("Shopping Lists"))

	btnRecents:SetScript("OnClick", function()
		sidebarMode = "RECENTS"
		LoadSidebarItems()
	end)
	btnLists:SetScript("OnClick", function()
		sidebarMode = "LISTS"
		LoadSidebarItems()
	end)

	-- Sidebar ScrollFrame
	listScroll = CreateFrame("ScrollFrame", "Atr_BuyListScroll", panel.sidebar, "FauxScrollFrameTemplate")
	listScroll:SetPoint("TOPLEFT", panel.sidebar, "TOPLEFT", 0, -80)
	listScroll:SetPoint("BOTTOMRIGHT", panel.sidebar, "BOTTOMRIGHT", -22, 6)
	listScroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, 33, Atr_RenderBuySidebar)
	end)

	-- Sidebar Rows (10 rows)
	for i = 1, 10 do
		local row = CreateFrame("Button", "Atr_BuySidebarRow" .. i, panel.sidebar)
		row:SetHeight(33)
		row:SetPoint("LEFT", panel.sidebar, "LEFT", 4, 0)
		row:SetPoint("RIGHT", panel.sidebar, "RIGHT", -24, 0)
		row:SetPoint("TOP", panel.sidebar, "TOP", 0, -80 - (i - 1) * 33)

		local highlight = row:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
		highlight:SetBlendMode("ADD")

		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(26, 26)
		row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)

		row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		row.nameText:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
		row.nameText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -1)
		row.nameText:SetJustifyH("LEFT")

		row.priceText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.priceText:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 2)
		row.priceText:SetJustifyH("LEFT")

		row:SetScript("OnEnter", function(self)
			if self.data and self.data.name then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				if self.data.link then
					GameTooltip:SetHyperlink(self.data.link)
				else
					GameTooltip:AddLine(self.data.name, 1, 0.82, 0)
				end
				GameTooltip:Show()
			end
		end)
		row:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		row:SetScript("OnClick", function(self)
			if self.data and self.data.name then
				stagedItem = self.data
				selectedListing = nil
				TriggerBuySearch(self.data.name)
				UpdateStagedItemDisplay()
			end
		end)

		sidebarRows[i] = row
	end

	-- ------------------------------------------------------------------------
	-- Column 2: Staging & Checkout Terminal (~290px)
	-- ------------------------------------------------------------------------
	panel.staging = CreateFrame("Frame", "Atr_BuyStagingPanel", panel)
	panel.staging:SetPoint("TOPLEFT", panel.sidebar, "TOPRIGHT", 8, 0)
	panel.staging:SetPoint("BOTTOMLEFT", panel.sidebar, "BOTTOMRIGHT", 8, 0)
	panel.staging:SetWidth(290)
	Atr_AnalysisBackdrop(panel.staging, 1, "body")

	-- Header: Icon + Name + iLvl/Req + Availability
	stagedIcon = panel.staging:CreateTexture(nil, "ARTWORK")
	stagedIcon:SetSize(40, 40)
	stagedIcon:SetPoint("TOPLEFT", panel.staging, "TOPLEFT", 12, -10)
	stagedIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

	stagedName = panel.staging:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	stagedName:SetPoint("TOPLEFT", stagedIcon, "TOPRIGHT", 10, -2)
	stagedName:SetPoint("TOPRIGHT", panel.staging, "TOPRIGHT", -10, -2)
	stagedName:SetJustifyH("LEFT")
	stagedName:SetText("|cff888888" .. Z("No item selected") .. "|r")

	stagedDetails = panel.staging:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	stagedDetails:SetPoint("TOPLEFT", stagedIcon, "TOPRIGHT", 10, -20)
	stagedDetails:SetPoint("TOPRIGHT", panel.staging, "TOPRIGHT", -10, -20)
	stagedDetails:SetJustifyH("LEFT")
	stagedDetails:SetText(Z("Select an item from the left sidebar to start buying"))

	stagedAvailable = panel.staging:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	stagedAvailable:SetPoint("TOPLEFT", stagedIcon, "BOTTOMLEFT", 0, -6)
	stagedAvailable:SetPoint("TOPRIGHT", panel.staging, "TOPRIGHT", -10, -6)
	stagedAvailable:SetJustifyH("LEFT")

	-- Reference Pricing Cards Container
	local refContainer = CreateFrame("Frame", nil, panel.staging)
	refContainer:SetPoint("TOPLEFT", panel.staging, "TOPLEFT", 10, -70)
	panel.refContainer = refContainer
	refContainer:SetPoint("TOPRIGHT", panel.staging, "TOPRIGHT", -10, -70)
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
	refMarketVal = MakeRefCard(Z("Market Median"), 105)
	refDiscountVal = MakeRefCard(Z("Market %"), 200)

	-- Quick Quantity Buttons
	local qtyPresets = {
		{ label = "1 " .. Z("Item"), mode = "1", width = 86 },
		{ label = "1 " .. Z("Stacks:"), mode = "stack", width = 86 },
		{ label = Z("Buy All"), mode = "all", width = 86 },
	}
	local prevQtyBtn = nil
	for _, q in ipairs(qtyPresets) do
		local b = CreateFrame("Button", nil, panel.staging, "UIPanelButtonTemplate")
		Atr_AnalysisSkin(b, "Button")
		b:SetSize(q.width, 22)
		if not prevQtyBtn then
			b:SetPoint("TOPLEFT", refContainer, "BOTTOMLEFT", 0, -10)
		else
			b:SetPoint("LEFT", prevQtyBtn, "RIGHT", 5, 0)
		end
		b:SetText(q.label)
		b:SetScript("OnClick", function()
			if not selectedListing then
				return
			end
			local stackSize = selectedListing.stackSize or 1
			local maxCount = selectedListing.count or 1
			if q.mode == "1" then
				numItemsEdit:SetText(1)
				numStacksEdit:SetText(1)
			elseif q.mode == "stack" then
				numItemsEdit:SetText(stackSize)
				numStacksEdit:SetText(1)
			elseif q.mode == "all" then
				numItemsEdit:SetText(stackSize * maxCount)
				numStacksEdit:SetText(maxCount)
			end
			RecalculateCart()
		end)
		prevQtyBtn = b
	end

	-- Quantity Inputs
	local qtyLabel = panel.staging:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	qtyLabel:SetPoint("TOPLEFT", prevQtyBtn, "BOTTOMLEFT", 0, -10)
	qtyLabel:SetText(Z("Quantity") .. " (" .. Z("Per Item") .. " / " .. Z("Stacks:") .. "):")

	numItemsEdit = CreateFrame("EditBox", "Atr_BuyNumItems", panel.staging, "InputBoxTemplate")
	Atr_AnalysisSkin(numItemsEdit, "EditBox")
	numItemsEdit:SetNumeric(true)
	numItemsEdit:SetAutoFocus(false)
	numItemsEdit:SetSize(60, 20)
	numItemsEdit:SetPoint("TOPLEFT", qtyLabel, "BOTTOMLEFT", 0, -4)
	numItemsEdit:SetScript("OnTextChanged", function(self)
		if selectedListing then
			local sz = selectedListing.stackSize or 1
			local n = self:GetNumber() or 1
			if numStacksEdit and not numStacksEdit:HasFocus() then
				numStacksEdit:SetText(math.max(1, math.ceil(n / sz)))
			end
		end
		RecalculateCart()
	end)

	local multSign = panel.staging:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	multSign:SetPoint("LEFT", numItemsEdit, "RIGHT", 8, 0)
	multSign:SetText("/")

	numStacksEdit = CreateFrame("EditBox", "Atr_BuyNumStacks", panel.staging, "InputBoxTemplate")
	Atr_AnalysisSkin(numStacksEdit, "EditBox")
	numStacksEdit:SetNumeric(true)
	numStacksEdit:SetAutoFocus(false)
	numStacksEdit:SetSize(60, 20)
	numStacksEdit:SetPoint("LEFT", multSign, "RIGHT", 8, 0)
	numStacksEdit:SetScript("OnTextChanged", function(self)
		if selectedListing then
			local sz = selectedListing.stackSize or 1
			local stacks = self:GetNumber() or 1
			if numItemsEdit and not numItemsEdit:HasFocus() then
				numItemsEdit:SetText(stacks * sz)
			end
		end
		RecalculateCart()
	end)

	-- Financial Summary
	local sum1 = panel.staging:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sum1:SetPoint("TOPLEFT", numItemsEdit, "BOTTOMLEFT", 0, -14)
	sum1:SetText(Z("Unit Price") .. ": ")
	unitPriceVal = panel.staging:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	unitPriceVal:SetPoint("LEFT", sum1, "RIGHT", 4, 0)
	unitPriceVal:SetText("--")

	local sum2 = panel.staging:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	sum2:SetPoint("TOPLEFT", sum1, "BOTTOMLEFT", 0, -8)
	sum2:SetText(Z("Total to Pay:") .. " ")
	totalCostVal = panel.staging:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
	totalCostVal:SetPoint("LEFT", sum2, "RIGHT", 4, 0)
	totalCostVal:SetText("--")

	local sum3 = panel.staging:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sum3:SetPoint("TOPLEFT", sum2, "BOTTOMLEFT", 0, -8)
	sum3:SetText(Z("Your Balance:") .. " ")
	playerBalanceVal = panel.staging:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	playerBalanceVal:SetPoint("LEFT", sum3, "RIGHT", 4, 0)
	playerBalanceVal:SetText(money((GetMoney and GetMoney()) or 0))

	balanceStatus = panel.staging:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	balanceStatus:SetPoint("TOPLEFT", sum3, "BOTTOMLEFT", 0, -6)
	balanceStatus:SetText("")

	-- Big Buy Button
	buyBtn = CreateFrame("Button", "Atr_BuyExecuteButton", panel.staging, "UIPanelButtonTemplate")
	Atr_AnalysisSkin(buyBtn, "Button")
	buyBtn:SetSize(266, 34)
	buyBtn:SetPoint("BOTTOM", panel.staging, "BOTTOM", 0, 8)
	buyBtn:SetText(Z("Buy"))
	buyBtn:SetScript("OnClick", ExecutePurchase)

	-- ------------------------------------------------------------------------
	-- Column 3: Live Market Depth (~270px)
	-- ------------------------------------------------------------------------
	panel.market = CreateFrame("Frame", "Atr_BuyMarketDepthPanel", panel)
	panel.market:SetPoint("TOPLEFT", panel.staging, "TOPRIGHT", 8, 0)
	panel.market:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 30)
	Atr_AnalysisBackdrop(panel.market, 1, "body")

	depthHeaderTitle = panel.market:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	depthHeaderTitle:SetPoint("TOPLEFT", panel.market, "TOPLEFT", 10, -10)
	depthHeaderTitle:SetText(Z("Market Competitors"))

	depthStatusBadge = panel.market:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	depthStatusBadge:SetPoint("TOPLEFT", depthHeaderTitle, "BOTTOMLEFT", 0, -4)
	depthStatusBadge:SetText("|cff55aaff● " .. Z("No Competitors") .. "|r")

	local refreshBtn = CreateFrame("Button", nil, panel.market, "UIPanelButtonTemplate")
	Atr_AnalysisSkin(refreshBtn, "Button")
	refreshBtn:SetSize(72, 20)
	refreshBtn:SetPoint("TOPRIGHT", panel.market, "TOPRIGHT", -10, -8)
	refreshBtn:SetText(Z("Refresh"))
	refreshBtn:SetScript("OnClick", function()
		if stagedItem and stagedItem.name then
			TriggerBuySearch(stagedItem.name)
		end
	end)

	-- Depth Table Headers
	local thPrice = panel.market:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	thPrice:SetPoint("TOPLEFT", panel.market, "TOPLEFT", 10, -42)
	thPrice:SetText(Z("Unit Price"))

	local thStacks = panel.market:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	thStacks:SetPoint("LEFT", thPrice, "LEFT", 110, 0)
	thStacks:SetText(Z("Stacks:"))

	local thSeller = panel.market:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	thSeller:SetPoint("LEFT", thStacks, "LEFT", 70, 0)
	thSeller:SetText(Z("Seller"))

	-- Depth ScrollFrame
	depthScroll = CreateFrame("ScrollFrame", "Atr_BuyDepthScroll", panel.market, "FauxScrollFrameTemplate")
	depthScroll:SetPoint("TOPLEFT", panel.market, "TOPLEFT", 0, -58)
	depthScroll:SetPoint("BOTTOMRIGHT", panel.market, "BOTTOMRIGHT", -22, 6)
	depthScroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, 26, Atr_RenderMarketDepth)
	end)

	-- Depth Rows (11 rows)
	for i = 1, 11 do
		local row = CreateFrame("Button", "Atr_BuyDepthRow" .. i, panel.market)
		row:SetHeight(26)
		row:SetPoint("LEFT", panel.market, "LEFT", 4, 0)
		row:SetPoint("RIGHT", panel.market, "RIGHT", -24, 0)
		row:SetPoint("TOP", panel.market, "TOP", 0, -58 - (i - 1) * 26)

		local highlight = row:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
		highlight:SetBlendMode("ADD")

		row.selectedBg = row:CreateTexture(nil, "BACKGROUND")
		row.selectedBg:SetAllPoints()
		row.selectedBg:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
		row.selectedBg:SetVertexColor(1, 0.8, 0.2, 0.4)
		row.selectedBg:Hide()

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
			if self.data then
				selectedListing = self.data
				if numItemsEdit then
					numItemsEdit:SetText(self.data.stackSize or 1)
				end
				if numStacksEdit then
					numStacksEdit:SetText(1)
				end
				RecalculateCart()
				Atr_RenderMarketDepth()
			end
		end)

		row:SetScript("OnEnter", function(self)
			if self.data then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:AddLine(Z("Click to match price") or "Click to select listing", 1, 0.82, 0)
				GameTooltip:AddDoubleLine(Z("Buyout Price"), money(self.data.buyoutPrice or 0), 1, 1, 1)
				GameTooltip:Show()
			end
		end)
		row:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)

		depthRows[i] = row
	end

	-- ------------------------------------------------------------------------
	-- Panel Scripts & Lifecycle
	-- ------------------------------------------------------------------------
	panel:SetScript("OnShow", function(self)
		Atr_AnalysisFit(self)
		artwork = Atr_AnalysisBegin(self)
		if Atr_StyleAnalysisScroll then
			Atr_StyleAnalysisScroll(listScroll, panel.sidebar)
			Atr_StyleAnalysisScroll(depthScroll, panel.market)
		end
		LoadSidebarItems()
		UpdateStagedItemDisplay()
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

	panel:Hide()
end

-- ============================================================================
-- Integration & Hooks
-- ============================================================================
function Atr_UpdateBuyTabVisibility()
	if not AuctionFrame or not AuctionFrame:IsShown() then
		return
	end

	local useModern = (AUCTIONATOR_SAVEDVARS and AUCTIONATOR_SAVEDVARS.modernBuy ~= false)
	local isBuyTab = (Atr_IsTabSelected and Atr_IsTabSelected(2)) -- BUY_TAB is 2

	if isBuyTab and useModern then
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
		if isBuyTab and not useModern and Atr_Main_Panel and not Atr_Main_Panel:IsShown() then
			Atr_Main_Panel:Show()
		end
	end
end

AuctionatorRemastered.Legacy.Hook("Atr_AuctionFrameTab_OnClick", function()
	Atr_UpdateBuyTabVisibility()
end)

AuctionatorRemastered.Legacy.Hook("Atr_Shop_OnFinishScan", function()
	if panel and panel:IsShown() then
		if gShopPane and gShopPane.activeScan then
			local itemName = gShopPane.activeScan.itemName
			local name, itemLink, itemRarity, itemLevel, minLevel, itemTypeStr, _, _, _, itemTexture =
				GetItemInfo(itemName or "")
			stagedItem = {
				name = name or itemName or "Unknown",
				link = itemLink or gShopPane.activeScan.itemLink,
				texture = itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark",
				quality = itemRarity or 1,
				ilvl = itemLevel or 0,
				reqLevel = minLevel or 0,
				type = itemTypeStr or "",
			}
			selectedListing = nil
			UpdateStagedItemDisplay()
		end
	end
end)

AuctionatorRemastered.Legacy.Hook("Atr_Init", function()
	MakeBuyTerminal()
end)
