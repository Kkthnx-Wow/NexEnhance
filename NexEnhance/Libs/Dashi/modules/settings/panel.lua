local addonName, addon = ...

local function onSettingChanged(owner, setting, value)
	if owner then
		-- triggered by player changing settings in the panel
		addon:SetOption(setting:GetVariable(), value)
	else
		-- triggered by addon.SetOption
		setting:SetValue(value)
	end
end

local function formatCustom(fmt, value)
	return fmt:format(value)
end

local function registerSetting(category, info)
	local setting = Settings.RegisterAddOnSetting(category, info.title, info.key, type(info.default), info.default)
	if info.type == "toggle" then
		Settings.CreateCheckBox(category, setting, info.tooltip)
	elseif info.type == "slider" then
		local sliderOptions = Settings.CreateSliderOptions(info.minValue, info.maxValue, info.valueStep or 1)
		local valueFormat
		if type(info.valueFormat) == "string" then
			valueFormat = GenerateClosure(formatCustom, info.valueFormat)
		elseif type(info.valueFormat) == "function" then
			valueFormat = info.valueFormat
		end
		sliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, valueFormat)
		Settings.CreateSlider(category, setting, sliderOptions, info.tooltip)
	elseif info.type == "menu" then
		local getMenuOptions = function()
			local container = Settings.CreateControlTextContainer()
			for key, name in next, info.options do
				container:Add(key, name)
			end
			return container:GetData()
		end
		Settings.CreateDropDown(category, setting, getMenuOptions, info.tooltip)
	end

	-- hook into both the Settings object and Dashi's option callback for value changes
	Settings.SetOnValueChangedCallback(info.key, onSettingChanged)
	addon:RegisterOptionCallback(info.key, GenerateClosure(onSettingChanged, nil, setting))
end

local function internalRegisterSettings(savedvariable, settings)
	-- create a vertical layout category, handing off all elements to Blizzard
	local category = Settings.RegisterVerticalLayoutCategory(C_AddOns.GetAddOnMetadata(addonName, "Title"))

	-- iterate through the provided settings table and generate settings objects and defaults
	local defaults = {}
	for _, info in next, settings do
		registerSetting(category, info)
		defaults[info.key] = info.default
	end

	-- register category and load the savedvariables
	Settings.RegisterAddOnCategory(category)
	addon:LoadOptions(savedvariable, defaults)
end

local isRegistered
--[[ namespace:RegisterSettings(_savedvariables_, _settings_)
Registers a set of `settings` with the interface options panel.  
The values will be stored by the `settings`' objects' `key` in `savedvariables`.

Should be used with the options methods below.

Usage:
```lua
namespace:RegisterSettings('MyAddOnDB', {
    {
        key = 'myToggle',
        title = 'My Toggle',
        tooltip = 'Longer description of the toggle in a tooltip',
        default = false,
    }
    {
        key = 'mySlider',
        type = 'slider',
        title = 'My Slider',
        tooltip = 'Longer description of the slider in a tooltip',
        default = 0.5,
        minValue = 0.1,
        maxValue = 1.0,
        valueStep = 0.01,
        valueFormat = formatter, -- callback function or a string for string.format
    },
    {
        key = 'myMenu',
        type = 'menu',
        title = 'My Menu',
        tooltip = 'Longer description of the menu in a tooltip',
        options = {
            key1 = 'First option',
            key2 = 'Second option',
            key3 = 'Third option',
        }
    }
})
```
--]]
function addon:RegisterSettings(savedvariable, settings)
	assert(not isRegistered, "can't register settings more than once")
	isRegistered = true

	-- ensure we only add the panel after savedvariables are available to the client
	local _, isReady = IsAddOnLoaded(addonName)
	if isReady then
		internalRegisterSettings(savedvariable, settings)
	else
		-- don't abuse OnLoad internally
		addon:RegisterEvent("ADDON_LOADED", function(_, name)
			if name == addonName then
				internalRegisterSettings(savedvariable, settings)
				return true -- unregister
			end
		end)
	end
end

--[[ namespace:RegisterSettingsSlash(_..._)
Wrapper for `namespace:RegisterSlash(...)`, except the callback is provided and will open the interface options for this addon.
--]]
function addon:RegisterSettingsSlash(...)
	-- gotta do this dumb shit because `..., callback` is not valid Lua
	local data = { ... }
	table.insert(data, function()
		-- iterate over all categories until we find ours, since OpenToCategory only takes ID
		local categoryID
		local settingsName = C_AddOns.GetAddOnMetadata(addonName, "Title")
		for _, category in next, SettingsPanel:GetAllCategories() do
			if category.name == settingsName then
				assert(not categoryID, "found multiple instances of the same category")
				categoryID = category:GetID()
			end
		end

		Settings.OpenToCategory(categoryID)
	end)

	addon:RegisterSlash(unpack(data))
end
