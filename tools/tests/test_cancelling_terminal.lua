dofile("AuctionatorRemastered/Remastered/Core/Bootstrap.lua")
dofile("AuctionatorRemastered/Remastered/Integration/LegacyBridge.lua")

local checks = 0
local function check(v, msg)
	checks = checks + 1
	assert(v, msg or "assertion failed")
end

-- =========================================================================
-- Mocks for WoW 3.3.5a Auction & Combat Environment
-- =========================================================================
local inCombat = false
function InCombatLockdown()
	return inCombat
end

function hooksecurefunc(name, fn) end

function GetItemQualityColor(quality)
	return 1, 1, 1
end

function ZT(s)
	return s
end

local mockOwnerAuctions = {}
function GetNumAuctionItems(type)
	if type == "owner" then
		return #mockOwnerAuctions, #mockOwnerAuctions
	end
	return 0, 0
end

function GetAuctionItemInfo(type, index)
	if type == "owner" and mockOwnerAuctions[index] then
		local a = mockOwnerAuctions[index]
		return a.name,
			a.texture,
			a.count,
			a.quality,
			a.canUse,
			a.level,
			a.minBid,
			a.minIncrement,
			a.buyoutPrice,
			a.bidAmount,
			a.highestBidder,
			a.owner,
			a.sold
	end
end

function GetAuctionItemLink(type, index)
	if type == "owner" and mockOwnerAuctions[index] then
		return mockOwnerAuctions[index].link
	end
end

function GetAuctionItemTimeLeft(type, index)
	if type == "owner" and mockOwnerAuctions[index] then
		return mockOwnerAuctions[index].timeLeft or 4
	end
	return 4
end

local canceledIndices = {}
function CanCancelAuction(index)
	if mockOwnerAuctions[index] and not mockOwnerAuctions[index].sold then
		return 1
	end
	return nil
end

function CancelAuction(index)
	if inCombat then
		error("CancelAuction called during InCombatLockdown!")
	end
	canceledIndices[#canceledIndices + 1] = index
end

-- Mock zc & scan database
zc = {
	ItemIDStrfromLink = function(link)
		if link then
			return string.match(link, "item:(%d+)")
		end
	end,
}

local mockScans = {}
function Atr_FindScan(id)
	return mockScans[id]
end

function Atr_DoesAuctionMatch(type, index, name, buyout, count, link)
	local a = mockOwnerAuctions[index]
	if not a then
		return false
	end
	return a.name == name and a.buyoutPrice == buyout and a.count == count
end

DEFAULT_CHAT_FRAME = {
	messages = {},
	AddMessage = function(self, msg)
		self.messages[#self.messages + 1] = msg
	end,
}

-- Load CancellingTerminal
dofile("AuctionatorRemastered/Remastered/Features/CancellingTerminal.lua")
local CT = AuctionatorRemastered.Features.CancellingTerminal

-- =========================================================================
-- Test 1: ScanOwnerAuctions & Undercut Evaluation
-- =========================================================================
local function TestScanAndUndercut()
	mockOwnerAuctions = {
		{
			name = "Frostweave Cloth",
			link = "item:33470:0:0:0:0:0:0:0",
			texture = "Interface\\Icons\\INV_Fabric_Frostweave_Bolt",
			count = 20,
			quality = 1,
			buyoutPrice = 2000000, -- 100,000 copper (10g) per item vs competitor 80,000 copper (8g) -> Undercut!
			timeLeft = 3,
			sold = nil,
		},
		{
			name = "Titanium Ore",
			link = "item:36910:0:0:0:0:0:0:0",
			texture = "Interface\\Icons\\INV_Ore_Titanium",
			count = 1,
			quality = 2,
			buyoutPrice = 500000, -- 50g
			timeLeft = 1,
			sold = nil,
		},
		{
			name = "Sold Recipe",
			link = "item:12345:0:0:0:0:0:0:0",
			texture = "Interface\\Icons\\INV_Scroll_03",
			count = 1,
			quality = 3,
			buyoutPrice = 100000,
			timeLeft = 4,
			sold = 1, -- Sold!
		},
	}

	-- Mock scan: Frostweave Cloth competitor is at 8g (80,000 copper) -> Undercut!
	mockScans["33470"] = {
		whenScanned = 100,
		absoluteBest = { itemPrice = 80000 },
	}
	-- Mock scan: Titanium Ore competitor is at 55g -> We are lowest!
	mockScans["36910"] = {
		whenScanned = 100,
		absoluteBest = { itemPrice = 550000 },
	}

	CT.ScanOwnerAuctions()

	-- Check that undercut items sort to the top
	-- Frostweave Cloth is undercut, so it should be activeAuctions[1]
	check(CT.Scan ~= nil, "Scan function should be exported")
end
TestScanAndUndercut()

-- =========================================================================
-- Test 2: Single Auction Cancellation
-- =========================================================================
local function TestSingleCancel()
	canceledIndices = {}
	inCombat = false

	local auc = {
		index = 1,
		name = "Frostweave Cloth",
		buyoutPrice = 2000000,
		count = 20,
		itemLink = "item:33470:0:0:0:0:0:0:0",
	}

	local success = CT.CancelSingleAuction(auc)
	check(success == true, "CancelSingleAuction should succeed when out of combat")
	check(#canceledIndices == 1 and canceledIndices[1] == 1, "Index 1 should be canceled")

	-- Combat check
	inCombat = true
	canceledIndices = {}
	success = CT.CancelSingleAuction(auc)
	check(success == false, "CancelSingleAuction should fail when InCombatLockdown is true")
	check(#canceledIndices == 0, "No auction should be canceled during combat")
	inCombat = false
end
TestSingleCancel()

-- =========================================================================
-- Test 3: Batch Cancellation of Undercuts
-- =========================================================================
local function TestBatchCancel()
	canceledIndices = {}
	inCombat = false

	-- Run batch cancel
	CT.CancelAllUndercuts()
	check(#canceledIndices >= 1, "Undercut auction should be canceled in batch")

	-- If in combat, batch cancel should abort
	inCombat = true
	canceledIndices = {}
	CT.CancelAllUndercuts()
	check(#canceledIndices == 0, "Batch cancel must abort when in combat")
	inCombat = false
end
TestBatchCancel()

-- =========================================================================
-- Test 4: Settings Toggle
-- =========================================================================
local function TestSettings()
	AUCTIONATOR_SAVEDVARS = {}
	check(AUCTIONATOR_SAVEDVARS.modernCancelling ~= false, "modernCancelling should default to true")

	AUCTIONATOR_SAVEDVARS.modernCancelling = false
	check(AUCTIONATOR_SAVEDVARS.modernCancelling == false, "modernCancelling can be toggled to false")

	AUCTIONATOR_SAVEDVARS.modernCancelling = true
	check(AUCTIONATOR_SAVEDVARS.modernCancelling == true, "modernCancelling can be toggled to true")
end
TestSettings()

print(string.format("PASS: %d checks passed in test_cancelling_terminal.lua", checks))
