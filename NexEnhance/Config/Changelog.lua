local addonName, Config = ...

local pairs, gsub = pairs, gsub

local changelogEntries = {
	"Enhanced options for better usability.",
	"Code cleanup and added a new inventory module.",
	"Currently navigating through some challenges...",
	"Updated the QuestReward module along with various other improvements.",
	"Introduced a new AFK module and additional settings.",
}

-- Function to create the changelog GUI
local function CreateChangelogGUI()
	local majorVersion = gsub(Config.Version, "%.%d+$", ".0")
	local changelogFrame = CreateFrame("Frame", addonName)
	changelogFrame.name = "Changelog"
	changelogFrame.parent = addonName

	local title = changelogFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetText(majorVersion .. " " .. changelogFrame.name)
	title:SetPoint("TOP", changelogFrame, "TOP", 0, -15)

	local description = changelogFrame:CreateFontString("$parentDescription", "ARTWORK", "GameFontHighlight")
	description:SetPoint("TOP", title, "BOTTOM", 0, -8)
	description:SetText("Find the latest updates, improvements, and bug fixes here.")

	local backgroundImage = changelogFrame:CreateTexture(nil, "BACKGROUND")
	backgroundImage:SetTexture(Config.Logo256)
	backgroundImage:SetBlendMode("BLEND")
	backgroundImage:SetAlpha(0.1)
	backgroundImage:SetPoint("CENTER", changelogFrame)

	local offset = 0
	local indexAtlas = "|A:ui-ej-icon-empoweredraid-small:14:14|a"
	for index, entry in pairs(changelogEntries) do
		local change = changelogFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
		change:SetPoint("TOPLEFT", changelogFrame, "TOPLEFT", 15, -(100 + offset))
		change:SetText(indexAtlas .. " " .. entry)
		if index % 2 == 0 then
			change:SetTextColor(0.8, 0.8, 0.8) -- Slightly off-white
		else
			change:SetTextColor(1, 1, 1) -- White
		end
		offset = offset + 28 -- Adjusted for larger font size
	end

	InterfaceOptions_AddCategory(changelogFrame) -- DEPRECATED
	return changelogFrame
end

-- Create the changelog GUI once
function Config.CreateChangelogGUI()
	Config.CreateChangelogGUI = Config.Dummy -- Ensure this is only executed once
	CreateChangelogGUI()
end
