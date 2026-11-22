-- tools/tests/test_sales_tracker.lua
-- Unit test suite for Passive Mail Sales Tracker (AUCTIONATOR_SALES) and TradingLogs integration.

local checks = 0
local function check(ok, msg)
	checks = checks + 1
	if not ok then
		error("CHECK FAILED: " .. tostring(msg), 2)
	end
end

-- Mock WoW environment
local currentTime = 1700000000
function time()
	return currentTime
end
function date(fmt, t)
	return "2026-11-22 12:00"
end
function GetRealmName()
	return "TestRealm"
end
function UnitFactionGroup(unit)
	return "Alliance"
end
function UnitName(unit)
	return "TestPlayer"
end

local registeredEvents = {}
local registeredScripts = {}

local frameMock = {
	RegisterEvent = function(self, evt)
		registeredEvents[evt] = true
	end,
	SetScript = function(self, handler, fn)
		registeredScripts[handler] = fn
	end,
}

function CreateFrame(kind, name, parent)
	return frameMock
end

ERR_AUCTION_SOLD_S = "A buyer has been found for your auction of %s."

-- Mock Item Catalog / GetItemInfo
function GetItemInfo(name)
	if name == "Frostweave Cloth" then
		return "Frostweave Cloth", "|cffffffff|Hitem:33470:0:0:0:0:0:0:0:80|h[Frostweave Cloth]|h|r"
	end
	return nil
end

-- Setup global namespace
_G.AuctionatorRemastered = {
	Models = {
		ItemIdentity = {
			Parse = function(link)
				return link and link:match("item:(%d+)")
			end,
		},
	},
}

-- Setup own auctions mock
_G.AUCTIONATOR_OWN_AUCTIONS = {
	TestRealm_Alliance = {
		since = currentTime - 86400,
		records = {
			{
				name = "Frostweave Cloth",
				link = "|cffffffff|Hitem:33470:0:0:0:0:0:0:0:80|h[Frostweave Cloth]|h|r",
				itemKey = "33470",
				when = currentTime - 7200,
				stackSize = 20,
				stacks = 5,
				stackPrice = 50000, -- 5g per stack of 20
				character = "TestPlayer",
			},
		},
	},
}

-- Load Sales.lua
assert(loadfile("AuctionatorRemastered/Remastered/Data/Sales.lua"))()

-- Test 1: Event registration
check(registeredEvents["MAIL_INBOX_UPDATE"] == true, "MAIL_INBOX_UPDATE registered")
check(registeredEvents["MAIL_SHOW"] == true, "MAIL_SHOW registered")
check(registeredEvents["CHAT_MSG_SYSTEM"] == true, "CHAT_MSG_SYSTEM registered")
check(type(registeredScripts["OnEvent"]) == "function", "OnEvent script handler registered")

-- Test 2: Mock Mailbox data
local inboxMails = {}

function GetInboxNumItems()
	return #inboxMails
end

function GetInboxInvoiceInfo(index)
	local m = inboxMails[index]
	if not m or not m.isInvoice then
		return nil
	end
	return m.invoiceType, m.itemName, m.playerName, m.bid, m.buyout, m.deposit, m.consignment
end

function GetInboxHeaderInfo(index)
	local m = inboxMails[index]
	if not m then
		return nil
	end
	return nil, nil, m.sender, m.subject, m.money, 0, m.daysLeft, 0, 0, nil, nil, nil, nil, m.quantity
end

-- Scenario A: Empty inbox
local added = Atr_ScanMailboxForSales()
check(added == 0, "Empty inbox adds 0 sales")

-- Scenario B: Add a single sold auction invoice
inboxMails[1] = {
	isInvoice = true,
	invoiceType = "seller",
	itemName = "Frostweave Cloth",
	playerName = "BuyerOne",
	bid = 50000,
	buyout = 50000,
	deposit = 100,
	consignment = 2500,
	sender = "Auction House",
	subject = "Auction successful: Frostweave Cloth",
	money = 47600, -- 50000 + 100 - 2500
	daysLeft = 29.98,
	quantity = nil,
}

added = Atr_ScanMailboxForSales()
check(added == 1, "First scan of sold mail records 1 sale")

local ledger = Atr_GetSalesLedger()
check(#ledger == 1, "Ledger contains 1 record")
local rec = ledger[1]
check(rec.name == "Frostweave Cloth", "Recorded item name matches")
check(rec.buyer == "BuyerOne", "Recorded buyer matches")
check(rec.stackPrice == 50000, "Recorded sale price matches")
check(rec.deposit == 100, "Recorded deposit matches")
check(rec.consignment == 2500, "Recorded consignment cut matches")
check(rec.net == 47600, "Recorded net matches (bid + deposit - cut)")
check(rec.stackSize == 20, "Stack size resolved from own auctions listing (20)")
check(rec.character == "TestPlayer", "Character matches seller")

-- Scenario C: Rescanning same inbox (same mailbox session) -> Deduplication
added = Atr_ScanMailboxForSales()
check(added == 0, "Rescanning identical inbox adds 0 duplicate sales")
check(#ledger == 1, "Ledger still has exactly 1 record")

-- Scenario D: Time passes (1 hour later, daysLeft decreases by 1/24 day) -> Deduplication survives
currentTime = currentTime + 3600
inboxMails[1].daysLeft = 29.98 - (3600 / 86400)
added = Atr_ScanMailboxForSales()
check(added == 0, "Rescanning after time passes adds 0 duplicate sales")
check(#ledger == 1, "Ledger still has exactly 1 record")

-- Scenario E: Second identical sale arrives (e.g. buyer bought another stack)
inboxMails[2] = {
	isInvoice = true,
	invoiceType = "seller",
	itemName = "Frostweave Cloth",
	playerName = "BuyerOne",
	bid = 50000,
	buyout = 50000,
	deposit = 100,
	consignment = 2500,
	sender = "Auction House",
	subject = "Auction successful: Frostweave Cloth",
	money = 47600,
	daysLeft = inboxMails[1].daysLeft, -- same arrival time
	quantity = nil,
}

added = Atr_ScanMailboxForSales()
check(added == 1, "Second identical mail adds exactly 1 new record")
check(#ledger == 2, "Ledger now has 2 records")

-- Rescanning with 2 identical mails
added = Atr_ScanMailboxForSales()
check(added == 0, "Rescanning 2 identical mails adds 0 duplicates")
check(#ledger == 2, "Ledger remains at 2 records")

-- Scenario F: Player loots one of the mails (inbox count drops to 1)
table.remove(inboxMails, 1)
check(#inboxMails == 1, "Inbox now has 1 mail left")
added = Atr_ScanMailboxForSales()
check(added == 0, "Looting one mail does not duplicate or corrupt ledger")
check(#ledger == 2, "Ledger retains historical sales count (2)")

-- Scenario G: Buyer invoice (buying an item, not selling) -> ignored
inboxMails[#inboxMails + 1] = {
	isInvoice = true,
	invoiceType = "buyer",
	itemName = "Saronite Bar",
	playerName = "SellerGuy",
	bid = 80000,
	buyout = 80000,
	deposit = 0,
	consignment = 0,
	sender = "Auction House",
	subject = "Auction won: Saronite Bar",
	money = 0,
	daysLeft = 29.5,
}

added = Atr_ScanMailboxForSales()
check(added == 0, "Buyer invoices are ignored by sales scanner")
check(#ledger == 2, "Ledger unaffected by buyer invoice")

-- Scenario H: A new distinct sale arrives
inboxMails[#inboxMails + 1] = {
	isInvoice = true,
	invoiceType = "seller",
	itemName = "Titanium Ore (2)",
	playerName = "MinerDave",
	bid = 120000,
	buyout = 120000,
	deposit = 200,
	consignment = 6000,
	sender = "Auction House",
	subject = "Auction successful: Titanium Ore (2)",
	money = 114200,
	daysLeft = 29.99,
}

added = Atr_ScanMailboxForSales()
check(added == 1, "New distinct sale recorded")
check(#ledger == 3, "Ledger now has 3 records")
local rec3 = ledger[3]
check(rec3.name == "Titanium Ore (2)", "Distinct item recorded")
check(rec3.buyer == "MinerDave", "Distinct buyer recorded")
check(rec3.stackPrice == 120000, "Price recorded")
check(rec3.stackSize == 2, "Stack size parsed from (2) suffix")

-- Test 3: CHAT_MSG_SYSTEM notifications
check(#Atr_GetPendingSales() == 0, "Pending sales starts empty")
registeredScripts["OnEvent"](
	frameMock,
	"CHAT_MSG_SYSTEM",
	"A buyer has been found for your auction of Frostweave Cloth."
)
check(#Atr_GetPendingSales() == 1, "Chat alert captured in pending sales")
check(Atr_GetPendingSales()[1].name == "Frostweave Cloth", "Item name parsed from chat")

-- Unrelated chat
registeredScripts["OnEvent"](frameMock, "CHAT_MSG_SYSTEM", "Random player says: hello")
check(#Atr_GetPendingSales() == 1, "Unrelated chat ignored")

Atr_ClearPendingSales()
check(#Atr_GetPendingSales() == 0, "Atr_ClearPendingSales cleared list")

-- Test 4: Atr_BuildSaleRows
local saleRows = Atr_BuildSaleRows("Frostweave Cloth")
check(#saleRows == 2, "BuildSaleRows returned 2 rows for Frostweave Cloth")
check(saleRows[1].buyer == "BuyerOne", "Sale row has buyer")
check(saleRows[1].status == "Sold", "Sale row status is 'Sold'")
check(saleRows[1].type == "sale", "Sale row type is 'sale'")
check(saleRows[1].itemPrice == 2500, "Item price unit is 50000 / 20 = 2500")

-- Test 5: Integration with Models/TradingLogs.lua
_G.AUCTIONATOR_PURCHASES = {
	TestRealm_Alliance = {
		since = currentTime - 86400,
		records = {
			{
				name = "Netherweave Cloth",
				link = nil,
				itemKey = nil,
				when = currentTime - 3000,
				stackSize = 20,
				stacks = 1,
				stackPrice = 15000,
				character = "TestPlayer",
				seller = "SomeoneElse",
			},
		},
	},
}

assert(loadfile("AuctionatorRemastered/Remastered/Models/TradingLogs.lua"))()

-- Query All
local records, spent, listed, bought, offered, earned, sold = Atr_GetTradingLogs("All", "", 30, nil)
check(#records == 5, "TradingLogs 'All' includes 1 bought + 1 listed + 3 sold = 5 records")
check(spent == 15000, "Spent = 15000 (Netherweave Cloth)")
check(listed == 250000, "Listed = 250000 (5 stacks of 50000 Frostweave Cloth)")
check(bought == 20, "Bought count = 20")
check(offered == 100, "Offered count = 5 * 20 = 100")
check(earned == 220000, "Earned = 50000 + 50000 + 120000 = 220000")
check(sold == 42, "Sold count = 20 + 20 + 2 = 42")

-- Query Sold only
local soldRecords, s_spent, s_listed, s_bought, s_offered, s_earned, s_sold = Atr_GetTradingLogs("Sold", "", 30, nil)
check(#soldRecords == 3, "TradingLogs 'Sold' returns exactly 3 sold records")
check(s_earned == 220000, "Sold filter earned = 220000")
check(s_sold == 42, "Sold filter items = 42")
check(s_spent == 0, "Sold filter spent is 0")
check(s_listed == 0, "Sold filter listed is 0")

-- Query Bought only
local boughtRecords = Atr_GetTradingLogs("Bought", "", 30, nil)
check(#boughtRecords == 1, "TradingLogs 'Bought' returns exactly 1 record")
check(boughtRecords[1].name == "Netherweave Cloth", "Bought record is Netherweave Cloth")

-- Query with text search
local searchResults = Atr_GetTradingLogs("All", "Titanium", 30, nil)
check(#searchResults == 1, "Search for 'Titanium' matches 1 record")
check(searchResults[1].name == "Titanium Ore (2)", "Search result name matches")
check(searchResults[1].buyer == "MinerDave", "Search result has buyer")

-- Net profit
local netProfit = earned - spent
check(netProfit == 205000, "Net profit = 220000 - 15000 = 205000 copper")

-- Backwards compatibility with 5-return call
local _, oldSpent, oldListed, oldBought, oldOffered = Atr_GetTradingLogs("All", "", 30, nil)
check(
	oldSpent == 15000 and oldListed == 250000 and oldBought == 20 and oldOffered == 100,
	"5-return call retains exact backwards-compatible values"
)

print("PASS: " .. checks .. " checks passed in test_sales_tracker.lua")
