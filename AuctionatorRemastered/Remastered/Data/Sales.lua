-- Remastered/Data/Sales.lua
-- Passive sales tracking via mail invoices and auction sale chat notifications.
-- Zero UI injection into MailFrame to prevent conflicts with Postal, TSM, DragonUI, etc.

local function ledger()
	if type(AUCTIONATOR_SALES) ~= "table" then
		AUCTIONATOR_SALES = {}
	end
	local key = GetRealmName() .. "_" .. UnitFactionGroup("player")
	if not AUCTIONATOR_SALES[key] then
		AUCTIONATOR_SALES[key] = { since = time(), records = {} }
	end
	return AUCTIONATOR_SALES[key]
end

local pendingAlerts = {}

function Atr_GetPendingSales()
	return pendingAlerts
end

function Atr_ClearPendingSales()
	pendingAlerts = {}
end

function Atr_GetSalesLedger()
	return ledger().records
end

-- Resolve stack size and link from listing history or item name
local function resolveSaleDetails(itemName, bid, buyout)
	local link, stackSize, itemKey
	local countFromListing = nil

	-- Check if player posted this recently in AUCTIONATOR_OWN_AUCTIONS
	if type(AUCTIONATOR_OWN_AUCTIONS) == "table" then
		local key = GetRealmName() .. "_" .. UnitFactionGroup("player")
		local own = AUCTIONATOR_OWN_AUCTIONS[key]
		if own and type(own.records) == "table" then
			for i = #own.records, 1, -1 do
				local rec = own.records[i]
				if rec.name == itemName then
					if not link and rec.link then
						link = rec.link
						itemKey = rec.itemKey
					end
					if (rec.stackPrice == bid or rec.stackPrice == buyout) and not countFromListing then
						countFromListing = rec.stackSize
						if rec.link then
							link = rec.link
							itemKey = rec.itemKey
						end
						break
					end
				end
			end
		end
	end

	-- If not found in own auctions, try GetItemInfo
	if not link and GetItemInfo then
		local _, itemLink = GetItemInfo(itemName)
		if itemLink then
			link = itemLink
			local identity = AuctionatorRemastered
				and AuctionatorRemastered.Models
				and AuctionatorRemastered.Models.ItemIdentity
			if identity and identity.Parse then
				itemKey = identity.Parse(itemLink)
			end
		end
	end

	-- Stack size fallback:
	-- 1) from matching listing
	-- 2) or parsed from name "Item Name (20)"
	-- 3) fallback 1
	if countFromListing and countFromListing > 0 then
		stackSize = countFromListing
	else
		local countFromName = itemName:match("%((%d+)%)$")
		if countFromName then
			stackSize = tonumber(countFromName) or 1
		else
			stackSize = 1
		end
	end

	return link, stackSize, itemKey
end

-- Scan the mailbox for sold auction invoices
function Atr_ScanMailboxForSales()
	if not GetInboxNumItems then
		return 0
	end
	local numItems = GetInboxNumItems()
	if not numItems or numItems <= 0 then
		return 0
	end

	local log = ledger()
	local newSalesCount = 0
	local now = time()

	-- 1. Gather all seller invoices currently in the inbox
	local currentInvoices = {}
	for i = 1, numItems do
		local invoiceType, itemName, playerName, bid, buyout, deposit, consignment = GetInboxInvoiceInfo(i)
		if invoiceType == "seller" and itemName and itemName ~= "" then
			local _, _, _, _, _, _, daysLeft = GetInboxHeaderInfo(i)
			local expireTime = math.floor(now + (daysLeft or 30) * 86400 + 0.5)
			local finalPrice = (buyout and buyout > 0) and buyout or (bid or 0)
			deposit = deposit or 0
			consignment = consignment or 0
			currentInvoices[#currentInvoices + 1] = {
				index = i,
				itemName = itemName,
				buyer = playerName or "",
				price = finalPrice,
				deposit = deposit,
				consignment = consignment,
				net = finalPrice + deposit - consignment,
				expireTime = expireTime,
			}
		end
	end

	if #currentInvoices == 0 then
		return 0
	end

	-- 2. Deduplicate against existing records
	-- Group invoices by signature (item + buyer + price + deposit + consignment)
	-- and match within a 300-second expiration window
	for _, inv in ipairs(currentInvoices) do
		local matchingInboxCount = 0
		for _, other in ipairs(currentInvoices) do
			if
				other.itemName == inv.itemName
				and other.buyer == inv.buyer
				and other.price == inv.price
				and other.deposit == inv.deposit
				and other.consignment == inv.consignment
				and math.abs(other.expireTime - inv.expireTime) <= 300
			then
				matchingInboxCount = matchingInboxCount + 1
			end
		end

		local matchingRecordCount = 0
		for _, rec in ipairs(log.records) do
			if
				rec.name == inv.itemName
				and (rec.buyer or "") == inv.buyer
				and rec.stackPrice == inv.price
				and (rec.deposit or 0) == inv.deposit
				and (rec.consignment or 0) == inv.consignment
				and rec.expireTime
				and math.abs(rec.expireTime - inv.expireTime) <= 300
			then
				matchingRecordCount = matchingRecordCount + 1
			end
		end

		if matchingInboxCount > matchingRecordCount then
			-- We have more identical invoices in the inbox than previously recorded
			local link, stackSize, itemKey = resolveSaleDetails(inv.itemName, inv.price, inv.price)
			log.records[#log.records + 1] = {
				name = inv.itemName,
				link = link,
				itemKey = itemKey,
				buyer = inv.buyer,
				stackSize = stackSize,
				stackPrice = inv.price,
				stacks = 1,
				deposit = inv.deposit,
				consignment = inv.consignment,
				net = inv.net,
				when = now,
				character = UnitName("player"),
				expireTime = inv.expireTime,
			}
			newSalesCount = newSalesCount + 1

			-- Prune ancient records (>5000 or >180 days)
			while #log.records > 5000 or (#log.records > 0 and log.records[1].when < now - 180 * 86400) do
				table.remove(log.records, 1)
			end
		end
	end

	return newSalesCount
end

-- Build sale rows for price history / item info
function Atr_BuildSaleRows(itemName)
	local log, rows = ledger(), {}
	for _, record in ipairs(log.records) do
		if record.name == itemName then
			local size = record.stackSize or 1
			local stacks = record.stacks or 1
			local total = record.stackPrice * stacks
			rows[#rows + 1] = {
				when = record.when,
				itemPrice = record.stackPrice / size,
				stackSize = size,
				stacks = stacks,
				quantity = size * stacks,
				total = total,
				buyer = record.buyer,
				character = record.character,
				yours = true,
				type = "sale",
				ownLedger = true,
				status = "Sold",
				whenText = date("%Y-%m-%d %H:%M", record.when),
			}
		end
	end
	table.sort(rows, function(a, b)
		return a.when > b.when
	end)
	return rows
end

-- Frame to listen to mailbox events and chat messages
local frame = CreateFrame("Frame")
frame:RegisterEvent("MAIL_INBOX_UPDATE")
frame:RegisterEvent("MAIL_SHOW")
frame:RegisterEvent("CHAT_MSG_SYSTEM")
frame:SetScript("OnEvent", function(self, event, arg1)
	if event == "MAIL_INBOX_UPDATE" or event == "MAIL_SHOW" then
		Atr_ScanMailboxForSales()
	elseif event == "CHAT_MSG_SYSTEM" and arg1 then
		if ERR_AUCTION_SOLD_S then
			local pattern = ERR_AUCTION_SOLD_S
			pattern = pattern:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
			pattern = pattern:gsub("%%s", "(.+)")
			local soldItem = arg1:match("^" .. pattern .. "$")
			if soldItem then
				pendingAlerts[#pendingAlerts + 1] = {
					name = soldItem,
					when = time(),
					character = UnitName("player"),
				}
			end
		end
	end
end)
