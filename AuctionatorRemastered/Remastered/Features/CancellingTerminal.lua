-- ============================================================================
-- Auctionator Remastered - Modern Cancelling & Active Auctions Terminal
-- Replaces the classic 2008 Undercuts tab with a modern management interface
-- Features: Active listings table, time left, buyout/unit, undercut detection,
-- batch cancellation, instant filter, and combat lockdown safety.
-- ============================================================================

local R = AuctionatorRemastered or {}
AuctionatorRemastered = R

R.Features = R.Features or {}
R.Features.CancellingTerminal = {}
local CT = R.Features.CancellingTerminal

local panel
local searchBox, clearSearchBtn
local summaryBadge, cancelUndercutsBtn, checkUndercutsBtn, refreshBtn
local cancellingScroll
local rows = {}
local artwork = {}

local activeAuctions = {}
local filteredAuctions = {}

local function Z(s)
	return (ZT and ZT(s)) or s
end

local function money(v)
	if not v or v <= 0 then
		return "0|cffffd100g|r"
	end
	if gAtrZC and gAtrZC.priceToMoneyString then
		return gAtrZC.priceToMoneyString(v)
	end
	local g = math.floor(v / 10000)
	local s = math.floor((v % 10000) / 100)
	local c = v % 100
	if g > 0 then
		return string.format("%d|cffffd100g|r %d|cffe6e6e6s|r %d|cffc79c6ec|r", g, s, c)
	elseif s > 0 then
		return string.format("%d|cffe6e6e6s|r %d|cffc79c6ec|r", s, c)
	else
		return string.format("%d|cffc79c6ec|r", c)
	end
end

-- ============================================================================
-- Data Parsing & Undercut Evaluation
-- ============================================================================
function CT.ScanOwnerAuctions()
	activeAuctions = {}

	local count = 0
	if GetNumAuctionItems then
		count = GetNumAuctionItems("owner") or 0
	end

	local undercutCount = 0
	local totalValue = 0

	for i = 1, count do
		local name, texture, stackSize, quality, canUse, level, minBid, minIncrement, buyoutPrice, bidAmount, highestBidder, owner, sold =
			GetAuctionItemInfo("owner", i)

		if name then
			local itemLink = GetAuctionItemLink and GetAuctionItemLink("owner", i)
			local timeLeft = (GetAuctionItemTimeLeft and GetAuctionItemTimeLeft("owner", i)) or 4
			local canCancel = (CanCancelAuction and CanCancelAuction(i)) and true or false
			if sold then
				canCancel = false
			end

			stackSize = math.max(1, stackSize or 1)
			buyoutPrice = buyoutPrice or 0
			local unitBuyout = math.floor(buyoutPrice / stackSize)
			totalValue = totalValue + buyoutPrice

			local isUndercut = false
			local isLowest = false
			local undercutPrice = nil
			local undercutDiff = 0

			-- Check competitor prices from existing scan data
			if itemLink and zc and zc.ItemIDStrfromLink and Atr_FindScan and unitBuyout > 0 then
				local IDstring = zc.ItemIDStrfromLink(itemLink)
				local scan = Atr_FindScan(IDstring)
				if scan and scan.absoluteBest and (scan.whenScanned or 0) ~= 0 then
					local absBest = scan.absoluteBest.itemPrice or 0
					if absBest > 0 and unitBuyout > absBest then
						isUndercut = true
						undercutPrice = absBest
						undercutDiff = math.floor(((unitBuyout - absBest) / absBest) * 100)
						undercutCount = undercutCount + 1
					elseif absBest > 0 and unitBuyout <= absBest then
						isLowest = true
					end
				end
			end

			activeAuctions[#activeAuctions + 1] = {
				index = i,
				name = name,
				texture = texture or "Interface\\Icons\\INV_Misc_QuestionMark",
				count = stackSize,
				quality = quality or 1,
				canUse = canUse,
				level = level or 0,
				minBid = minBid or 0,
				minIncrement = minIncrement or 0,
				buyoutPrice = buyoutPrice,
				unitBuyout = unitBuyout,
				bidAmount = bidAmount or 0,
				highestBidder = highestBidder,
				owner = owner,
				sold = sold,
				itemLink = itemLink,
				timeLeft = timeLeft,
				canCancel = canCancel,
				isUndercut = isUndercut,
				isLowest = isLowest,
				undercutPrice = undercutPrice,
				undercutDiff = undercutDiff,
			}
		end
	end

	-- Sort: Undercuts first, then by timeLeft (shortest first), then name
	table.sort(activeAuctions, function(a, b)
		if a.isUndercut ~= b.isUndercut then
			return a.isUndercut
		end
		if a.timeLeft ~= b.timeLeft then
			return a.timeLeft < b.timeLeft
		end
		return a.name < b.name
	end)

	CT.FilterAuctions()
	CT.UpdateSummary(count, undercutCount, totalValue)
end

function CT.UpdateSummary(totalLots, undercutCount, totalValue)
	if summaryBadge then
		summaryBadge:SetText(
			string.format(
				"|cffffffff%s:|r %d  |  |cffff5555%s:|r %d  |  |cffffd100%s:|r %s",
				Z("Active Lots"),
				totalLots,
				Z("Undercuts"),
				undercutCount,
				Z("Total Value"),
				money(totalValue)
			)
		)
	end

	if cancelUndercutsBtn then
		cancelUndercutsBtn:SetText(string.format(Z("Cancel Undercut (%d)"), undercutCount))
		if undercutCount > 0 and not (InCombatLockdown and InCombatLockdown()) then
			cancelUndercutsBtn:Enable()
		else
			cancelUndercutsBtn:Disable()
		end
	end
end

function CT.FilterAuctions()
	filteredAuctions = {}
	local filter = searchBox and searchBox:GetText() or ""
	filter = string.lower(string.gsub(filter, "^%s*(.-)%s*$", "%1"))

	for _, auc in ipairs(activeAuctions) do
		if filter == "" or string.find(string.lower(auc.name), filter, 1, true) then
			filteredAuctions[#filteredAuctions + 1] = auc
		end
	end

	CT.RenderRows()
end

-- ============================================================================
-- Rendering
-- ============================================================================
local TIME_LEFT_TEXTS = {
	[1] = "|cffff5555<30m|r",
	[2] = "|cffffaa00<2h|r",
	[3] = "|cffffff55<12h|r",
	[4] = "|cff55ff55>12h|r",
}

function CT.RenderRows()
	if not cancellingScroll then
		return
	end

	local numRecords = #filteredAuctions
	local visibleRows = #rows
	FauxScrollFrame_Update(cancellingScroll, numRecords, visibleRows, 28)

	local offset = FauxScrollFrame_GetOffset(cancellingScroll)
	local inCombat = InCombatLockdown and InCombatLockdown()

	for i, row in ipairs(rows) do
		local index = offset + i
		local auc = filteredAuctions[index]
		row.data = auc

		if auc and index <= numRecords then
			row.icon:SetTexture(auc.texture)
			if auc.count > 1 then
				row.countText:SetText(auc.count)
			else
				row.countText:SetText("")
			end

			-- Quality color
			local r, g, b = GetItemQualityColor(auc.quality or 1)
			row.nameText:SetText(string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, auc.name))

			-- Time Left
			row.timeText:SetText(TIME_LEFT_TEXTS[auc.timeLeft] or "--")

			-- Bid
			if auc.bidAmount and auc.bidAmount > 0 then
				row.bidText:SetText(money(auc.bidAmount))
			else
				row.bidText:SetText("|cff888888--|r")
			end

			-- Buyout
			if auc.buyoutPrice and auc.buyoutPrice > 0 then
				if auc.count > 1 then
					row.buyoutText:SetText(
						string.format("%s\n|cff888888(%s/ea)|r", money(auc.buyoutPrice), money(auc.unitBuyout))
					)
				else
					row.buyoutText:SetText(money(auc.buyoutPrice))
				end
			else
				row.buyoutText:SetText("|cff888888--|r")
			end

			-- Status
			if auc.sold then
				row.statusText:SetText("|cffffaa00● " .. Z("Sold / Pending") .. "|r")
			elseif auc.isUndercut then
				row.statusText:SetText(
					string.format("|cffff5555⚠️ " .. Z("Undercut (-%d%%)") .. "|r", auc.undercutDiff or 0)
				)
			elseif auc.isLowest then
				row.statusText:SetText("|cff55dd55● " .. Z("Lowest Price!") .. "|r")
			else
				row.statusText:SetText("|cff888888● " .. Z("Not Scanned") .. "|r")
			end

			-- Cancel Button
			if auc.sold or not auc.canCancel or inCombat then
				row.cancelBtn:Disable()
			else
				row.cancelBtn:Enable()
			end

			row:Show()
		else
			row.data = nil
			row:Hide()
		end
	end
end

-- ============================================================================
-- Cancellation Actions
-- ============================================================================
function CT.CancelSingleAuction(auc)
	if not auc or not auc.index then
		return false
	end

	if InCombatLockdown and InCombatLockdown() then
		if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
			DEFAULT_CHAT_FRAME:AddMessage("|cffff5555[Auctionator]|r " .. Z("Cannot cancel auctions during combat."))
		end
		return false
	end

	if not CanCancelAuction(auc.index) then
		return false
	end

	if
		Atr_DoesAuctionMatch
		and not Atr_DoesAuctionMatch("owner", auc.index, auc.name, auc.buyoutPrice, auc.count, auc.itemLink)
	then
		return false
	end

	CancelAuction(auc.index)

	if AuctionatorSubtractFromScan and auc.itemLink then
		AuctionatorSubtractFromScan(auc.itemLink, auc.count, auc.buyoutPrice)
	end

	return true
end

function CT.CancelAllUndercuts()
	if InCombatLockdown and InCombatLockdown() then
		if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
			DEFAULT_CHAT_FRAME:AddMessage("|cffff5555[Auctionator]|r " .. Z("Cannot cancel auctions during combat."))
		end
		return
	end

	local count = GetNumAuctionItems and GetNumAuctionItems("owner") or 0
	local canceled = 0

	-- Iterate backwards to maintain stable indices during cancellation
	for i = count, 1, -1 do
		if InCombatLockdown and InCombatLockdown() then
			break
		end

		local name, _, stackSize, _, _, _, _, _, buyoutPrice, _, _, _, sold = GetAuctionItemInfo("owner", i)
		if name and not sold and CanCancelAuction(i) then
			local itemLink = GetAuctionItemLink and GetAuctionItemLink("owner", i)
			local unitBuyout = math.floor((buyoutPrice or 0) / math.max(1, stackSize or 1))

			if itemLink and zc and zc.ItemIDStrfromLink and Atr_FindScan and unitBuyout > 0 then
				local IDstring = zc.ItemIDStrfromLink(itemLink)
				local scan = Atr_FindScan(IDstring)
				if scan and scan.absoluteBest and (scan.whenScanned or 0) ~= 0 then
					local absBest = scan.absoluteBest.itemPrice or 0
					if absBest > 0 and unitBuyout > absBest then
						if
							not Atr_DoesAuctionMatch
							or Atr_DoesAuctionMatch("owner", i, name, buyoutPrice, stackSize, itemLink)
						then
							CancelAuction(i)
							canceled = canceled + 1
							if AuctionatorSubtractFromScan then
								AuctionatorSubtractFromScan(itemLink, stackSize, buyoutPrice)
							end
						end
					end
				end
			end
		end
	end

	if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
		DEFAULT_CHAT_FRAME:AddMessage(
			string.format("|cffffd100[Auctionator]|r " .. Z("Canceled %d undercut auctions."), canceled)
		)
	end

	CT.ScanOwnerAuctions()
end

-- ============================================================================
-- UI Construction
-- ============================================================================
local function MakeCancellingTerminal()
	if panel or not AuctionFrame then
		return
	end

	panel = CreateFrame("Frame", "Atr_CancellingTerminal", AuctionFrame)
	panel:SetSize(832, 447)
	panel:SetPoint("TOPLEFT", AuctionFrame, "TOPLEFT", 0, 0)
	panel:EnableMouse(true)

	-- Top Bar: Title & Search
	local title = panel:CreateFontString("Atr_CancellingTitle", "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -18)
	title:SetText(Z("Active Auctions & Cancelling"))

	summaryBadge = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	summaryBadge:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	summaryBadge:SetText(Z("Scanning active auctions..."))

	-- Search Input
	searchBox = CreateFrame("EditBox", "Atr_CancellingSearch", panel, "InputBoxTemplate")
	Atr_AnalysisSkin(searchBox, "EditBox")
	searchBox:SetSize(160, 20)
	searchBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -62)
	searchBox:SetAutoFocus(false)
	searchBox:SetScript("OnTextChanged", function(self)
		local t = self:GetText()
		if clearSearchBtn then
			if t and t ~= "" then
				clearSearchBtn:Show()
			else
				clearSearchBtn:Hide()
			end
		end
		CT.FilterAuctions()
	end)
	searchBox:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)

	clearSearchBtn = CreateFrame("Button", nil, panel)
	clearSearchBtn:SetSize(14, 14)
	clearSearchBtn:SetPoint("LEFT", searchBox, "RIGHT", -18, 0)
	clearSearchBtn:SetNormalTexture("Interface\\FriendsFrame\\ClearBroadcastIcon")
	clearSearchBtn:SetScript("OnClick", function()
		searchBox:SetText("")
		searchBox:ClearFocus()
	end)
	clearSearchBtn:Hide()

	-- Action Buttons
	checkUndercutsBtn = CreateFrame("Button", "Atr_CancellingCheckBtn", panel, "UIPanelButtonTemplate")
	Atr_AnalysisSkin(checkUndercutsBtn, "Button")
	checkUndercutsBtn:SetSize(145, 22)
	checkUndercutsBtn:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
	checkUndercutsBtn:SetText(Z("Check Undercuts"))
	checkUndercutsBtn:SetScript("OnClick", function()
		if Atr_CheckingActiveIdle then
			Atr_CheckingActiveIdle()
		end
		CT.ScanOwnerAuctions()
	end)

	cancelUndercutsBtn = CreateFrame("Button", "Atr_CancellingCancelAllBtn", panel, "UIPanelButtonTemplate")
	Atr_AnalysisSkin(cancelUndercutsBtn, "Button")
	cancelUndercutsBtn:SetSize(185, 22)
	cancelUndercutsBtn:SetPoint("LEFT", checkUndercutsBtn, "RIGHT", 8, 0)
	cancelUndercutsBtn:SetText(Z("Cancel Undercuts"))
	cancelUndercutsBtn:SetScript("OnClick", function()
		CT.CancelAllUndercuts()
	end)
	cancelUndercutsBtn:Disable()

	refreshBtn = CreateFrame("Button", "Atr_CancellingRefreshBtn", panel, "UIPanelButtonTemplate")
	Atr_AnalysisSkin(refreshBtn, "Button")
	refreshBtn:SetSize(80, 22)
	refreshBtn:SetPoint("LEFT", cancelUndercutsBtn, "RIGHT", 8, 0)
	refreshBtn:SetText(Z("Refresh"))
	refreshBtn:SetScript("OnClick", function()
		if GetOwnerAuctionItems then
			GetOwnerAuctionItems()
		end
		CT.ScanOwnerAuctions()
	end)

	-- ------------------------------------------------------------------------
	-- Table Column Headers
	-- ------------------------------------------------------------------------
	local tableTop = -94
	local colItem = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	colItem:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, tableTop)
	colItem:SetText(Z("Item"))
	colItem:SetWidth(250)
	colItem:SetJustifyH("LEFT")

	local colTime = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	colTime:SetPoint("LEFT", colItem, "RIGHT", 10, 0)
	colTime:SetText(Z("Time Left"))
	colTime:SetWidth(70)
	colTime:SetJustifyH("LEFT")

	local colBid = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	colBid:SetPoint("LEFT", colTime, "RIGHT", 10, 0)
	colBid:SetText(Z("Current Bid"))
	colBid:SetWidth(110)
	colBid:SetJustifyH("LEFT")

	local colBuyout = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	colBuyout:SetPoint("LEFT", colBid, "RIGHT", 10, 0)
	colBuyout:SetText(Z("Buyout Price"))
	colBuyout:SetWidth(130)
	colBuyout:SetJustifyH("LEFT")

	local colStatus = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	colStatus:SetPoint("LEFT", colBuyout, "RIGHT", 10, 0)
	colStatus:SetText(Z("Market Status"))
	colStatus:SetWidth(110)
	colStatus:SetJustifyH("LEFT")

	local colAction = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	colAction:SetPoint("LEFT", colStatus, "RIGHT", 10, 0)
	colAction:SetText(Z("Action"))
	colAction:SetWidth(60)
	colAction:SetJustifyH("CENTER")

	-- ------------------------------------------------------------------------
	-- Scrollable Table Rows
	-- ------------------------------------------------------------------------
	cancellingScroll = CreateFrame("ScrollFrame", "Atr_CancellingScrollFrame", panel, "FauxScrollFrameTemplate")
	cancellingScroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, tableTop - 18)
	cancellingScroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -36, 16)
	cancellingScroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, 28, CT.RenderRows)
	end)

	for i = 1, 11 do
		local row = CreateFrame("Button", "Atr_CancellingRow" .. i, panel)
		row:SetHeight(28)
		row:SetPoint("LEFT", panel, "LEFT", 16, 0)
		row:SetPoint("RIGHT", panel, "RIGHT", -36, 0)
		row:SetPoint("TOP", panel, "TOP", 0, tableTop - 18 - ((i - 1) * 28))

		local highlight = row:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
		highlight:SetBlendMode("ADD")

		-- Icon
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(22, 22)
		row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)

		row.countText = row:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
		row.countText:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 1, -1)

		-- Name
		row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
		row.nameText:SetWidth(220)
		row.nameText:SetJustifyH("LEFT")

		-- Time Left
		row.timeText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.timeText:SetPoint("LEFT", row, "LEFT", 276, 0)
		row.timeText:SetWidth(70)
		row.timeText:SetJustifyH("LEFT")

		-- Bid
		row.bidText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.bidText:SetPoint("LEFT", row, "LEFT", 356, 0)
		row.bidText:SetWidth(110)
		row.bidText:SetJustifyH("LEFT")

		-- Buyout
		row.buyoutText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.buyoutText:SetPoint("LEFT", row, "LEFT", 476, 0)
		row.buyoutText:SetWidth(130)
		row.buyoutText:SetJustifyH("LEFT")

		-- Status
		row.statusText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.statusText:SetPoint("LEFT", row, "LEFT", 616, 0)
		row.statusText:SetWidth(110)
		row.statusText:SetJustifyH("LEFT")

		-- Cancel Button
		row.cancelBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		Atr_AnalysisSkin(row.cancelBtn, "Button")
		row.cancelBtn:SetSize(60, 20)
		row.cancelBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
		row.cancelBtn:SetText(Z("Cancel"))
		row.cancelBtn:SetScript("OnClick", function()
			if row.data then
				CT.CancelSingleAuction(row.data)
				CT.ScanOwnerAuctions()
			end
		end)

		row:SetScript("OnEnter", function(self)
			if self.data and self.data.index then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				if GameTooltip.SetAuctionItem then
					GameTooltip:SetAuctionItem("owner", self.data.index)
				elseif self.data.itemLink then
					GameTooltip:SetHyperlink(self.data.itemLink)
				end
				GameTooltip:Show()
			end
		end)
		row:SetScript("OnLeave", function()
			if GameTooltip then
				GameTooltip:Hide()
			end
		end)

		rows[i] = row
	end

	-- Panel Scripts & Lifecycle
	panel:SetScript("OnShow", function(self)
		Atr_AnalysisFit(self)
		artwork = Atr_AnalysisBegin(self)
		if Atr_StyleAnalysisScroll then
			Atr_StyleAnalysisScroll(cancellingScroll, panel)
		end
		if GetOwnerAuctionItems then
			GetOwnerAuctionItems()
		end
		CT.ScanOwnerAuctions()
	end)

	panel:SetScript("OnHide", function()
		artwork = {}
		if searchBox then
			searchBox:ClearFocus()
		end
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)

	panel:RegisterEvent("AUCTION_OWNED_LIST_UPDATE")
	panel:RegisterEvent("PLAYER_REGEN_DISABLED")
	panel:RegisterEvent("PLAYER_REGEN_ENABLED")
	panel:SetScript("OnEvent", function(self, event)
		if event == "AUCTION_OWNED_LIST_UPDATE" then
			if panel:IsShown() then
				CT.ScanOwnerAuctions()
			end
		elseif event == "PLAYER_REGEN_DISABLED" then
			if cancelUndercutsBtn then
				cancelUndercutsBtn:Disable()
			end
			for _, r in ipairs(rows) do
				if r.cancelBtn then
					r.cancelBtn:Disable()
				end
			end
		elseif event == "PLAYER_REGEN_ENABLED" then
			if panel:IsShown() then
				CT.ScanOwnerAuctions()
			end
		end
	end)

	panel:Hide()
end

-- ============================================================================
-- Visibility & Tab Management
-- ============================================================================
function Atr_UpdateCancellingTabVisibility()
	if not AuctionFrame or not AuctionFrame:IsShown() then
		return
	end

	local useModern = (AUCTIONATOR_SAVEDVARS and AUCTIONATOR_SAVEDVARS.modernCancelling ~= false)
	local isUndercutTab = (Atr_IsTabSelected and Atr_IsTabSelected(2)) -- MORE_TAB (Undercuts) is 2

	if isUndercutTab and useModern then
		if Atr_Main_Panel and Atr_Main_Panel:IsShown() then
			Atr_Main_Panel:Hide()
		end
		if Atr_Hlist and Atr_Hlist:IsShown() then
			Atr_Hlist:Hide()
		end
		if Atr_Hlist_ScrollFrame and Atr_Hlist_ScrollFrame:IsShown() then
			Atr_Hlist_ScrollFrame:Hide()
		end
		if Atr_ActiveItems_Text and Atr_ActiveItems_Text:IsShown() then
			Atr_ActiveItems_Text:Hide()
		end
		if Atr_CheckActiveButton and Atr_CheckActiveButton:IsShown() then
			Atr_CheckActiveButton:Hide()
		end
		if panel and not panel:IsShown() then
			panel:Show()
		end
	else
		if panel and panel:IsShown() then
			panel:Hide()
		end
		if isUndercutTab and not useModern and Atr_Main_Panel and not Atr_Main_Panel:IsShown() then
			Atr_Main_Panel:Show()
			if Atr_Hlist then
				Atr_Hlist:Show()
			end
			if Atr_Hlist_ScrollFrame then
				Atr_Hlist_ScrollFrame:Show()
			end
			if Atr_ActiveItems_Text then
				Atr_ActiveItems_Text:Show()
			end
			if Atr_CheckActiveButton then
				Atr_CheckActiveButton:Show()
			end
		end
	end
end

AuctionatorRemastered.Legacy.Hook("Atr_AuctionFrameTab_OnClick", function()
	Atr_UpdateCancellingTabVisibility()
end)

AuctionatorRemastered.Legacy.Hook("Atr_Init", function()
	MakeCancellingTerminal()
end)

-- Public API
AuctionatorRemastered.Features.CancellingTerminal.Panel = panel
AuctionatorRemastered.Features.CancellingTerminal.Scan = CT.ScanOwnerAuctions
AuctionatorRemastered.Features.CancellingTerminal.CancelAllUndercuts = CT.CancelAllUndercuts
