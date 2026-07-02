--[[
	NexEnhance - Drag Frames
	-------------------------------------------------------------------------
	Lets you click-and-drag most Blizzard windows (loot, merchant, mail,
	character, professions, ...) to reposition them, instead of being locked
	to their default spot.

	Ported from NDui's Plugins/DragEmAll.lua (by emelio / NDui MOD, siweia),
	adapted to the NexEnhance framework. Movement uses StartMoving on the
	(non-combat) panel frames, so it is taint-safe.
--]]

local _, ns = ...
local L = ns.L

local _G = _G
local pairs, type = pairs, type
local gmatch = string.gmatch
local InCombatLockdown = InCombatLockdown

ns:RegisterDefaults({
	dragEmAll = {
		enable = true,
	},
})

local DragEmAll = ns:NewModule("DragEmAll", "dragEmAll", { group = "movers", title = L["Drag Frames"], order = 10 })

local eventHandles = {}
local eventsRegistered = false

-- ["FrameName"] = true  -> drag moves the frame's PARENT
-- ["FrameName"] = false -> drag moves the frame itself
-- For child frames without a global name use "Parent.ChildKey" (dots allowed).
local frames = {
	["AddonList"] = false,
	["ChannelFrame"] = false,
	["ChatConfigFrame"] = false,
	["CommunitiesFrame"] = false,
	["CooldownViewerSettings"] = false,
	["DressUpFrame"] = false,
	["FriendsFrame"] = false,
	["GossipFrame"] = false,
	["GuildInviteFrame"] = false,
	["GuildRegistrarFrame"] = false,
	["HelpFrame"] = false,
	["ItemTextFrame"] = false,
	["LootFrame"] = false,
	["MailFrame"] = false,
	["MerchantFrame"] = false,
	["ModelPreviewFrame"] = false,
	["OpenMailFrame"] = false,
	["PaperDollFrame"] = true,
	["PetitionFrame"] = false,
	["PVEFrame"] = false,
	["QuestFrame"] = false,
	["RaidParentFrame"] = false,
	["ReputationFrame"] = true,
	["SendMailFrame"] = true,
	["SplashFrame"] = false,
	["StackSplitFrame"] = false,
	["TabardFrame"] = false,
	["TaxiFrame"] = false,
	["TokenFrame"] = true,
	["TutorialFrame"] = false,
	["SettingsPanel"] = false,

	-- Bags: draggable but intentionally NOT persisted. Blizzard's
	-- UpdateContainerFrameAnchors re-pins them on the next bag open/update, so
	-- they snap back to the default spot rather than saving a position. The
	-- combined window covers the default layout; ContainerFrame1-6 cover the
	-- separate-bag layout (dragging the first/root bag moves the whole cluster).
	["ContainerFrameCombinedBags"] = false,
	["ContainerFrame1"] = false,
	["ContainerFrame2"] = false,
	["ContainerFrame3"] = false,
	["ContainerFrame4"] = false,
	["ContainerFrame5"] = false,
	["ContainerFrame6"] = false,
}

-- Frames provided by load-on-demand addons; hooked when that addon loads.
local lodFrames = {
	Blizzard_AchievementUI = { ["AchievementFrame"] = false, ["AchievementFrameHeader"] = true, ["AchievementFrameCategoriesContainer"] = "AchievementFrame", ["AchievementFrame.searchResults"] = false },
	Blizzard_AdventureMap = { ["AdventureMapQuestChoiceDialog"] = false },
	Blizzard_AlliedRacesUI = { ["AlliedRacesFrame"] = false },
	Blizzard_ArchaeologyUI = { ["ArchaeologyFrame"] = false },
	Blizzard_ArtifactUI = { ["ArtifactFrame"] = false, ["ArtifactRelicForgeFrame"] = false },
	Blizzard_AuctionHouseUI = { ["AuctionHouseFrame"] = false },
	Blizzard_AzeriteEssenceUI = { ["AzeriteEssenceUI"] = false },
	Blizzard_AzeriteRespecUI = { ["AzeriteRespecFrame"] = false },
	Blizzard_AzeriteUI = { ["AzeriteEmpoweredItemUI"] = false },
	Blizzard_BindingUI = { ["KeyBindingFrame"] = false, ["QuickKeybindFrame"] = false },
	Blizzard_BlackMarketUI = { ["BlackMarketFrame"] = false },
	Blizzard_Calendar = { ["CalendarFrame"] = false, ["CalendarCreateEventFrame"] = true, ["CalendarEventPickerFrame"] = false },
	Blizzard_ChallengesUI = { ["ChallengesKeystoneFrame"] = false },
	Blizzard_ClassTalentUI = { ["ClassTalentFrame"] = false },
	Blizzard_ClickBindingUI = { ["ClickBindingFrame"] = false },
	Blizzard_Collections = { ["WardrobeFrame"] = false, ["WardrobeOutfitEditFrame"] = false },
	Blizzard_CovenantRenown = { ["CovenantRenownFrame"] = false },
	Blizzard_CovenantSanctum = { ["CovenantSanctumFrame"] = false },
	Blizzard_EncounterJournal = { ["EncounterJournal"] = false },
	Blizzard_FlightMap = { ["FlightMapFrame"] = false },
	Blizzard_GenericTraitUI = { ["GenericTraitFrame"] = false },
	Blizzard_GMSurveyUI = { ["GMSurveyFrame"] = false },
	Blizzard_GuildBankUI = { ["GuildBankFrame"] = false, ["GuildBankEmblemFrame"] = true },
	Blizzard_GuildControlUI = { ["GuildControlUI"] = false },
	Blizzard_GuildRecruitmentUI = { ["CommunitiesGuildRecruitmentFrame"] = false },
	Blizzard_GuildUI = { ["GuildFrame"] = false, ["GuildRosterFrame"] = true, ["GuildFrame.TitleMouseover"] = true },
	Blizzard_InspectUI = { ["InspectFrame"] = false, ["InspectPVPFrame"] = true, ["InspectTalentFrame"] = true },
	Blizzard_IslandsPartyPoseUI = { ["IslandsPartyPoseFrame"] = false },
	Blizzard_IslandsQueueUI = { ["IslandsQueueFrame"] = false },
	Blizzard_ItemSocketingUI = { ["ItemSocketingFrame"] = false },
	Blizzard_ItemUpgradeUI = { ["ItemUpgradeFrame"] = false },
	Blizzard_LookingForGuildUI = { ["LookingForGuildFrame"] = false },
	Blizzard_MacroUI = { ["MacroFrame"] = false },
	Blizzard_ObliterumUI = { ["ObliterumForgeFrame"] = false },
	Blizzard_OrderHallUI = { ["OrderHallTalentFrame"] = false },
	Blizzard_ScrappingMachineUI = { ["ScrappingMachineFrame"] = false },
	Blizzard_Professions = { ["InspectRecipeFrame"] = false, ["ProfessionsFrame"] = false },
	Blizzard_ProfessionsCustomerOrders = { ["ProfessionsCustomerOrdersFrame"] = false },
	Blizzard_TalentUI = { ["PlayerTalentFrame"] = false, ["PVPTalentPrestigeLevelDialog"] = false },
	Blizzard_TimeManager = { ["TimeManagerFrame"] = false },
	Blizzard_TokenUI = { ["TokenFrame"] = true },
	Blizzard_TradeSkillUI = { ["TradeSkillFrame"] = false },
	Blizzard_TrainerUI = { ["ClassTrainerFrame"] = false },
	Blizzard_VoidStorageUI = { ["VoidStorageFrame"] = false, ["VoidStorageBorderFrameMouseBlockFrame"] = "VoidStorageFrame" },
	Blizzard_WeeklyRewards = { ["WeeklyRewardsFrame"] = false },
}

local parentFrame, hooked = {}, {}

local function MouseDownHandler(frame, button)
	if not ns.db.dragEmAll.enable then
		return
	end
	-- Don't start moving a Blizzard window mid-combat: a few of these frames
	-- carry secure children, and StartMoving on a protected frame is blocked in
	-- the lockdown. Combat is also exactly when you don't want to be dragging UI.
	if InCombatLockdown() then
		return
	end
	frame = parentFrame[frame] or frame
	if frame and button == "LeftButton" then
		frame:StartMoving()
		frame:SetUserPlaced(false)
	end
end

local function MouseUpHandler(frame, button)
	if not ns.db.dragEmAll.enable then
		return
	end
	frame = parentFrame[frame] or frame
	if frame and button == "LeftButton" then
		frame:StopMovingOrSizing()
	end
end

-- Post-hook the frame's mouse scripts. We use the widget HookScript so the
-- original handler keeps running (and so we never taint the script path the way
-- a raw SetScript wrapper would). OnMouseDown/OnMouseUp exist on every frame, so
-- HookScript is always valid here.
local function HookScript(frame, script, handler)
	if not frame.HookScript then
		return
	end
	frame:HookScript(script, handler)
end

local function HookFrame(name, moveParent)
	-- Resolve possibly-nested frame (dots walk into child keys).
	local frame = _G ---@type any
	for s in gmatch(name, "%w+") do
		if frame then
			frame = frame[s]
		end
	end
	if frame == _G then
		frame = nil
	end
	if not frame or hooked[name] then
		return
	end

	local parent
	if moveParent then
		parent = (type(moveParent) == "string") and _G[moveParent] or frame:GetParent()
		if not parent then
			return
		end
		parentFrame[frame] = parent
		parent:SetMovable(true)
		parent:SetClampedToScreen(false)
	end

	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(false)
	HookScript(frame, "OnMouseDown", MouseDownHandler)
	HookScript(frame, "OnMouseUp", MouseUpHandler)
	hooked[name] = true
end

local function HookFrames(list)
	for name, child in pairs(list) do
		HookFrame(name, child)
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function DragEmAll:RegisterModuleEvents()
	if eventsRegistered then
		return
	end
	eventsRegistered = true
	self:TrackEvent(eventHandles, "ADDON_LOADED", "ADDON_LOADED")
end

function DragEmAll:UnregisterModuleEvents()
	if not eventsRegistered then
		return
	end
	eventsRegistered = false
	ns:UnregisterModuleEventHandles(eventHandles)
end

function DragEmAll:ADDON_LOADED(addon)
	local frameList = lodFrames[addon]
	if frameList then
		HookFrames(frameList)
	end
end

function DragEmAll:OnEnable()
	if not ns.db.dragEmAll.enable then
		return
	end
	HookFrames(frames)
	self:RegisterModuleEvents()
end

function DragEmAll:OnDisable()
	self:UnregisterModuleEvents()
end

function DragEmAll:OnSettingChanged(key, value)
	if key == "enable" then
		if value then
			HookFrames(frames)
			self:RegisterModuleEvents()
		else
			self:UnregisterModuleEvents()
		end
	end
end

function DragEmAll:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Drag Frames"], L["Click and drag most Blizzard windows to move them."])
end
