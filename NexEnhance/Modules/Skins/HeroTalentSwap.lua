--[[
	NexEnhance - Hero Talent Swap
	-------------------------------------------------------------------------
	Right-click the hero talent button on the Talents pane to swap to your
	inactive hero tree. Left-click passes through normally.

	Blizzard refs: Blizzard_PlayerSpells HeroTalentsContainer.HeroSpecButton,
	C_Traits.SetSelection, C_ClassTalents APIs.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local C, L = ns.C, ns.L

local CreateFrame = CreateFrame
local CreateAtlasMarkup = CreateAtlasMarkup
local GameTooltip = GameTooltip
local UnitLevel = UnitLevel
local format = string.format

ns:RegisterDefaults({
	heroTalentSwap = {
		enable = true,
	},
})

local HeroTalentSwap = ns:NewModule("HeroTalentSwap", "heroTalentSwap", { group = "skins", title = L["Hero Talent Swap"], order = 45 })

local overlay
local RIGHT_CLICK_MARKUP = CreateAtlasMarkup("NPE_RightClick", 18, 18)

local function GetInactiveHeroSelection()
	local configID = C_ClassTalents.GetActiveConfigID()
	if not configID then
		return
	end

	local specIndex = C_SpecializationInfo.GetSpecialization()
	if not specIndex then
		return
	end
	local specID = C_SpecializationInfo.GetSpecializationInfo(specIndex)
	if not specID then
		return
	end

	local specs, requiredLevel = C_ClassTalents.GetHeroTalentSpecsForClassSpec(configID, specID)
	if not specs or requiredLevel > UnitLevel("player") then
		return
	end

	local activeTreeID = C_ClassTalents.GetActiveHeroTalentSpec()
	if not activeTreeID then
		return
	end

	local inactiveTreeID
	for _, treeID in ipairs(specs) do
		if treeID ~= activeTreeID then
			inactiveTreeID = treeID
			break
		end
	end
	if not inactiveTreeID then
		return
	end

	local inactiveTreeInfo = C_Traits.GetSubTreeInfo(configID, inactiveTreeID)
	if not inactiveTreeInfo or not inactiveTreeInfo.subTreeSelectionNodeIDs then
		return
	end

	for _, nodeID in ipairs(inactiveTreeInfo.subTreeSelectionNodeIDs) do
		local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
		if nodeInfo and nodeInfo.isVisible and nodeInfo.isAvailable then
			for _, entryID in ipairs(nodeInfo.entryIDs) do
				local entryInfo = C_Traits.GetEntryInfo(configID, entryID)
				if entryInfo and entryInfo.subTreeID == inactiveTreeID then
					return configID, nodeID, entryID, inactiveTreeInfo
				end
			end
		end
	end
end

local function OnOverlayEnter(self)
	local _, _, _, treeInfo = GetInactiveHeroSelection()
	if not treeInfo then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	local atlas = CreateAtlasMarkup(treeInfo.iconElementID, 16, 16)
	local classColor = C_ClassColor.GetClassColor(C.Player.class)
	GameTooltip:SetText(RIGHT_CLICK_MARKUP .. " " .. format(L["Hero Talent Swap Hint"], atlas, classColor:WrapTextInColorCode(treeInfo.name)))
	GameTooltip:Show()
end

local function OnOverlayLeave()
	GameTooltip:Hide()
end

local function OnOverlayClick(self, button)
	if button ~= "RightButton" then
		return
	end
	local configID, nodeID, entryID = GetInactiveHeroSelection()
	if configID then
		C_Traits.SetSelection(configID, nodeID, entryID)
		OnOverlayEnter(self)
	end
end

local function AttachOverlay()
	if not overlay or not PlayerSpellsFrame or not PlayerSpellsFrame.TalentsFrame then
		return
	end
	local container = PlayerSpellsFrame.TalentsFrame.HeroTalentsContainer
	local heroButton = container and container.HeroSpecButton
	if not heroButton then
		return
	end
	overlay:SetParent(heroButton)
	overlay:SetAllPoints()
	overlay:Show()
end

local function EnsureOverlay()
	if overlay then
		AttachOverlay()
		return
	end
	-- SetPassThroughButtons is protected; create early before combat.
	overlay = CreateFrame("Button", nil, UIParent)
	overlay:RegisterForClicks("RightButtonUp")
	overlay:SetPassThroughButtons("LeftButton")
	overlay:SetPropagateMouseMotion(true)
	overlay:Hide()
	overlay:SetScript("OnEnter", OnOverlayEnter)
	overlay:SetScript("OnLeave", OnOverlayLeave)
	overlay:SetScript("OnClick", OnOverlayClick)
	AttachOverlay()
end

function HeroTalentSwap:OnEnable()
	if not ns.db.heroTalentSwap.enable then
		return
	end
	ns:RegisterAddOnLoadedCallback("Blizzard_PlayerSpells", EnsureOverlay)
	EnsureOverlay()
	if PlayerSpellsFrame then
		AttachOverlay()
	end
end

function HeroTalentSwap:OnDisable()
	if overlay then
		overlay:Hide()
		overlay:SetParent(UIParent)
	end
end

function HeroTalentSwap:OnSettingChanged(key, value)
	if key == "enable" then
		if value then
			self:OnEnable()
		else
			self:OnDisable()
		end
	end
end

function HeroTalentSwap:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Hero Talent Swap"], L["Right-click the hero talent button on the Talents pane to swap to your inactive hero spec."])
end
