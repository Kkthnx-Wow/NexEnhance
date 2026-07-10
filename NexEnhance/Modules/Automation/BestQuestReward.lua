--[[
	NexEnhance - Best Quest Reward
	-------------------------------------------------------------------------
	When a quest offers multiple reward choices, marks the highest vendor-value
	option with a small gold coin. Visual only — does not click or claim.

	Quick Quest already auto-picks by sell price when automation is on; this
	module is for when you want the hint without auto-turn-in.

	Scoring mirrors QuickQuest (cashRewards overrides + GetItemInfo sell price)
	and multiplies by stack amount. Missing item data retries via RequestItemData.
--]]

local _, ns = ...
local F, L = ns.F, ns.L

local select = select
local GetNumQuestChoices = GetNumQuestChoices
local GetQuestItemLink = GetQuestItemLink
local GetQuestItemInfo = GetQuestItemInfo
local GetItemInfoFromHyperlink = GetItemInfoFromHyperlink
local C_Item_GetItemInfo = C_Item and C_Item.GetItemInfo
local CreateFrame = CreateFrame
local UIParent = UIParent
local C_Timer = C_Timer

-- Same special cash items QuickQuest uses so highlight and auto-pick agree.
local cashRewards = {
	[45724] = 1e5, -- Champion's Purse
	[64491] = 2e6, -- Royal Reward
	[138127] = 15,
	[138129] = 11,
	[138131] = 24,
	[138123] = 15,
	[138125] = 16,
	[138133] = 27,
}

ns:RegisterDefaults({
	bestQuestReward = {
		enable = true,
	},
})

local BestQuestReward = ns:NewModule("BestQuestReward", "bestQuestReward", {
	group = "automation",
	title = L["Best Quest Reward"],
	order = 25,
	since = "1.6.0",
})

local eventHandles = {}
local eventsRegistered = false
local coinFrame
local rewardPanelHooked = false
local pendingRequest

local function db()
	return ns.db.bestQuestReward
end

local function HideCoin()
	if coinFrame then
		coinFrame:Hide()
	end
end

local function EnsureCoin()
	if coinFrame then
		return coinFrame
	end

	coinFrame = CreateFrame("Frame", nil, UIParent)
	coinFrame:SetFrameStrata("HIGH")
	coinFrame:SetSize(20, 20)
	coinFrame:Hide()

	local icon = coinFrame:CreateTexture(nil, "OVERLAY")
	icon:SetAllPoints()
	icon:SetTexture("Interface\\BUTTONS\\UI-GroupLoot-Coin-Up")

	return coinFrame
end

local function HookRewardPanelHide()
	if rewardPanelHooked then
		return
	end
	local panel = _G.QuestFrameRewardPanel
	if not panel then
		return
	end
	rewardPanelHooked = true
	-- hooksecurefunc stays forever — gate with IsEnabled() like other Blizzard hooks.
	panel:HookScript("OnHide", function()
		if BestQuestReward:IsEnabled() then
			HideCoin()
			pendingRequest = nil
		end
	end)
end

-- Sell value for one choice index. Returns nil when item data is still loading.
local function ChoiceVendorValue(index)
	local link = GetQuestItemLink("choice", index)
	if not link then
		-- Prime the client so QUEST_COMPLETE can resolve on the next pass.
		GetQuestItemInfo("choice", index)
		return nil, true
	end

	local itemID = GetItemInfoFromHyperlink and GetItemInfoFromHyperlink(link)
	local sellPrice = C_Item_GetItemInfo and select(11, C_Item_GetItemInfo(link))
	if sellPrice == nil and itemID and ns.RequestItemData then
		return nil, false, itemID
	end

	if cashRewards[itemID] then
		sellPrice = cashRewards[itemID]
	end

	if not sellPrice then
		return 0
	end

	local _, _, amount = GetQuestItemInfo("choice", index)
	if amount and amount > 1 then
		return sellPrice * amount
	end
	return sellPrice
end

local function RefreshHighlight()
	if not db().enable then
		return
	end

	HideCoin()

	local choices = GetNumQuestChoices()
	if not choices or choices < 2 then
		return
	end

	local rewardsFrame = _G.QuestInfoRewardsFrame
	if not (rewardsFrame and rewardsFrame.RewardButtons) then
		return
	end

	local bestValue, bestIndex = 0, nil
	local pendingItemID

	for index = 1, choices do
		local value, needsPrime, itemID = ChoiceVendorValue(index)
		if needsPrime then
			-- Link not ready — retry once after the client caches the choice.
			C_Timer.After(0.25, function()
				if BestQuestReward:IsEnabled() and _G.QuestFrame and _G.QuestFrame:IsShown() then
					RefreshHighlight()
				end
			end)
			return
		end
		if itemID then
			pendingItemID = itemID
		elseif value and value > bestValue then
			bestValue, bestIndex = value, index
		end
	end

	if pendingItemID then
		if pendingRequest == pendingItemID then
			return
		end
		pendingRequest = pendingItemID
		ns:RequestItemData(pendingItemID, function()
			pendingRequest = nil
			if BestQuestReward:IsEnabled() and _G.QuestFrame and _G.QuestFrame:IsShown() then
				RefreshHighlight()
			end
		end)
		return
	end

	if not bestIndex or bestValue <= 0 then
		return
	end

	local btn = rewardsFrame.RewardButtons[bestIndex]
	if not (btn and btn.type == "choice") then
		return
	end

	local coin = EnsureCoin()
	coin:ClearAllPoints()
	coin:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -2, -2)
	coin:Show()
end

function BestQuestReward:QUEST_COMPLETE()
	RefreshHighlight()
end

function BestQuestReward:RegisterModuleEvents()
	if eventsRegistered then
		return
	end
	eventsRegistered = true
	HookRewardPanelHide()
	self:TrackEvent(eventHandles, "QUEST_COMPLETE")
end

function BestQuestReward:UnregisterModuleEvents()
	if not eventsRegistered then
		return
	end
	eventsRegistered = false
	ns:UnregisterModuleEventHandles(eventHandles)
	pendingRequest = nil
	HideCoin()
end

function BestQuestReward:OnEnable()
	if not db().enable then
		return
	end
	self:RegisterModuleEvents()
end

function BestQuestReward:OnDisable()
	self:UnregisterModuleEvents()
end

function BestQuestReward:OnSettingChanged(key)
	-- ApplyModuleSetting owns enable lifecycle.
	if key == "enable" then
		return
	end
end

function BestQuestReward:RegisterOptions(category, builder)
	builder:Checkbox(
		category,
		self,
		"enable",
		L["Enable Best Quest Reward"],
		L["Mark the highest vendor-value quest reward choice with a gold coin. Does not auto-pick — use Quick Quest for that."]
	)
end
