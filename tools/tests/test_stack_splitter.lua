-- ============================================================================
-- Unit Tests: Smart Bag Splitter & Auto-fill
-- Tests stack distributions, inventory remainders, and capacity validations.
-- ============================================================================

dofile("AuctionatorRemastered/Remastered/Core/Bootstrap.lua")
dofile("AuctionatorRemastered/Remastered/Models/StackSplitter.lua")

local checks = 0
local function check(v, msg)
    checks = checks + 1
    assert(v, msg or "assertion failed")
end

local SS = AuctionatorRemastered.Models.StackSplitter
check(SS ~= nil, "StackSplitter model should be loaded")

-- ----------------------------------------------------------------------------
-- Test 1: Global exports
-- ----------------------------------------------------------------------------
check(
    _G.Atr_CalculateSmartDistribution == SS.CalculateSmartDistribution,
    "Atr_CalculateSmartDistribution global export"
)
check(_G.Atr_GetRemainderPreset == SS.GetRemainderPreset, "Atr_GetRemainderPreset global export")
check(_G.Atr_ValidateStacking == SS.ValidateStacking, "Atr_ValidateStacking global export")

-- ----------------------------------------------------------------------------
-- Test 2: CalculateSmartDistribution
-- ----------------------------------------------------------------------------
-- Case A: Zero items in bags
local d0 = SS.CalculateSmartDistribution(0, 20)
check(d0.size == 20, "Zero items: default size is maxStack")
check(d0.count == 0, "Zero items: count is 0")
check(d0.posted == 0, "Zero items: posted is 0")
check(d0.remainder == 0, "Zero items: remainder is 0")
check(d0.isExact == true, "Zero items: isExact is true")
check(d0.summary == "No items in bags", "Zero items summary")

-- Case B: Single non-stackable item (gear, quest item)
local d1 = SS.CalculateSmartDistribution(1, 1)
check(d1.size == 1, "Single item: size is 1")
check(d1.count == 1, "Single item: count is 1")
check(d1.posted == 1, "Single item: posted is 1")
check(d1.remainder == 0, "Single item: remainder is 0")
check(d1.isExact == true, "Single item: isExact is true")
check(d1.summary == "Posting 1 item", "Single item summary")

-- Case C: Exactly one full stack
local d20 = SS.CalculateSmartDistribution(20, 20)
check(d20.size == 20, "20/20: size is 20")
check(d20.count == 1, "20/20: count is 1")
check(d20.posted == 20, "20/20: posted is 20")
check(d20.remainder == 0, "20/20: remainder is 0")
check(d20.isExact == true, "20/20: isExact is true")
check(d20.summary == "Posting 1 stack of 20", "Single full stack summary")

-- Case D: Multiple full stacks (100 cloth with max stack 20)
local d100 = SS.CalculateSmartDistribution(100, 20)
check(d100.size == 20, "100/20: size is 20")
check(d100.count == 5, "100/20: count is 5")
check(d100.posted == 100, "100/20: posted is 100")
check(d100.remainder == 0, "100/20: remainder is 0")
check(d100.isExact == true, "100/20: isExact is true")
check(d100.summary == "Posting all 100 items (5 × 20)", "Multiple full stacks summary")

-- Case E: Odd count leaving a remainder (73 cloth with max stack 20)
local d73 = SS.CalculateSmartDistribution(73, 20)
check(d73.size == 20, "73/20: size is 20")
check(d73.count == 3, "73/20: count is 3")
check(d73.posted == 60, "73/20: posted is 60")
check(d73.remainder == 13, "73/20: remainder is 13")
check(d73.isExact == false, "73/20: isExact is false")
check(d73.summary == "Posting 60 of 73 items (13 left in bags)", "Odd count remainder summary")

-- Case F: Fewer items than max stack (17 cloth with max stack 20)
local d17 = SS.CalculateSmartDistribution(17, 20)
check(d17.size == 17, "17/20: size caps at total count 17")
check(d17.count == 1, "17/20: count is 1")
check(d17.posted == 17, "17/20: posted is 17")
check(d17.remainder == 0, "17/20: remainder is 0")
check(d17.isExact == true, "17/20: isExact is true")
check(d17.summary == "Posting 1 stack of 17", "Fewer items summary")

-- Case G: Preferred stack size (73 items, maxStack 20, preferredSize 10)
local dPref = SS.CalculateSmartDistribution(73, 20, 10)
check(dPref.size == 10, "Preferred size honored: size is 10")
check(dPref.count == 7, "Preferred size: count is 7 (70 items)")
check(dPref.posted == 70, "Preferred size: posted is 70")
check(dPref.remainder == 3, "Preferred size: remainder is 3")
check(dPref.isExact == false, "Preferred size: isExact is false")

-- Case H: Preferred stack size exceeds maxStack (invalid preferred size ignored)
local dPrefInvalid = SS.CalculateSmartDistribution(73, 20, 50)
check(dPrefInvalid.size == 20, "Invalid preferred size (>maxStack) ignored: falls back to 20")
check(dPrefInvalid.count == 3, "Count is 3")

-- Case I: Preferred stack size exceeds totalCount
local dPrefHigh = SS.CalculateSmartDistribution(5, 20, 10)
check(dPrefHigh.size == 5, "Preferred size > totalCount: capped at totalCount 5")
check(dPrefHigh.count == 1, "Count is 1")
check(dPrefHigh.remainder == 0, "Remainder is 0")

-- ----------------------------------------------------------------------------
-- Test 3: GetRemainderPreset
-- ----------------------------------------------------------------------------
-- 73 items, 3 stacks of 20 posted (60 items) -> 13 left
local remSize, remCount = SS.GetRemainderPreset(73, 20, 3)
check(remSize == 13, "Remainder size is 13")
check(remCount == 1, "Remainder count is 1")

-- 100 items, 5 stacks of 20 posted -> exactly 0 left
remSize, remCount = SS.GetRemainderPreset(100, 20, 5)
check(remSize == 0, "No remainder: size is 0")
check(remCount == 0, "No remainder: count is 0")

-- Overflow situation (50 items, 3 stacks of 20 = 60 items requested)
remSize, remCount = SS.GetRemainderPreset(50, 20, 3)
check(remSize == 0, "Overflow: no remainder returned")
check(remCount == 0, "Overflow: count is 0")

-- No current stacks (0 stacks) -> whole inventory is remainder
remSize, remCount = SS.GetRemainderPreset(17, 20, 0)
check(remSize == 17, "Zero posted: remainder is 17")
check(remCount == 1, "Zero posted: count is 1")

-- ----------------------------------------------------------------------------
-- Test 4: ValidateStacking
-- ----------------------------------------------------------------------------
-- Valid exact
local valid, status, msg, needed = SS.ValidateStacking(100, 20, 5, 20)
check(valid == true, "100/20x5: valid")
check(status == "OK", "100/20x5: status OK")
check(needed == 100, "100/20x5: needed 100")
check(msg == "Posting all 100 items (5 × 20)", "100/20x5: message")

-- Valid with remainder
valid, status, msg, needed = SS.ValidateStacking(73, 20, 3, 20)
check(valid == true, "73/20x3: valid")
check(status == "OK", "73/20x3: status OK")
check(needed == 60, "73/20x3: needed 60")
check(msg == "Posting 60 of 73 items (13 left in bags)", "73/20x3: message with remainder")

-- Zero stack size
valid, status, msg = SS.ValidateStacking(50, 0, 2, 20)
check(valid == false, "Zero size: invalid")
check(status == "ZERO_SIZE", "Zero size: status ZERO_SIZE")
check(msg == "Stack size must be at least 1", "Zero size message")

-- Negative stack size
valid, status, msg = SS.ValidateStacking(50, -5, 2, 20)
check(valid == false, "Negative size: invalid")
check(status == "ZERO_SIZE", "Negative size: status ZERO_SIZE")
check(msg == "Stack size must be at least 1", "Negative size message")

-- Zero number of stacks
valid, status, msg = SS.ValidateStacking(50, 20, 0, 20)
check(valid == false, "Zero stacks: invalid")
check(status == "ZERO_COUNT", "Zero stacks: status ZERO_COUNT")
check(msg == "Number of stacks must be at least 1", "Zero stacks message")

-- Stack size exceeds item max stack
valid, status, msg = SS.ValidateStacking(100, 25, 2, 20)
check(valid == false, "Stack size > maxStack: invalid")
check(status == "MAX_STACK_EXCEEDED", "Status MAX_STACK_EXCEEDED")
check(msg == "Stack size cannot exceed max stack (20)", "Max stack exceeded message")

-- Overflow: player asks for more items than they have in bags
valid, status, msg, needed = SS.ValidateStacking(30, 20, 2, 20)
check(valid == false, "Overflow (needs 40, has 30): invalid")
check(status == "OVERFLOW", "Status OVERFLOW")
check(needed == 40, "Needed is 40")
check(msg == "⚠️ Need 40 items, only 30 in bags (missing 10)", "Overflow warning message")

print(string.format("PASS: %d checks passed in test_stack_splitter.lua", checks))
