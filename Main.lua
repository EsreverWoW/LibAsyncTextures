local Addon, private = ...

-- Builtins
local getmetatable = getmetatable
local next = next
local pairs = pairs
local print = print
local tremove = table.remove
local type = type

-- Globals
local dump = dump
local Event = Event
local InspectAddonCurrent = Inspect.Addon.Current
local UI = UI
local UtilityDispatch = Utility.Dispatch

local pendingList = {
--[[
	[addon] = {
		[*] = { frame, source, texture, weight, callback }
	}
]]
}
local pendingTextures = 0

local weights = {
	tiny = 1,
	small = 2,
	medium = 4,
	large = 8,
	huge = 16,
}

-- How many weghted loads are allowed per system update?
-- This parameter is a guesstimate and probably needs some tweaking.
local loadPerUpdate = 128

-- The public interface table
local public = { }
LibAsyncTextures = public

setfenv(1, private)

if(Addon.toc.debug) then
	log = print
else
	log = function() end
end


-- Private methods
-- ============================================================================

local function dumpList()
	print("pendingList")
	for k, v in pairs(pendingList) do
		print("#" .. k .. " = " .. #v)
	end
end

local previousIndex = nil
local function loadTextures()
	local loaded = 0
	local index = previousIndex
	local addon

	while(pendingTextures > 0 and loaded < loadPerUpdate) do
		-- Load the textures in round-robin fashion i.e.
		-- One texture per addon, cycling all addons
		index, addon = next(pendingList, index)
		if(addon and #addon > 0) then
			local entry = tremove(addon, 1)
			entry[1]:SetTexture(entry[2], entry[3])
			loaded = loaded + entry[4]
			pendingTextures = pendingTextures - 1
			if(entry[5]) then
				UtilityDispatch(function() entry[5](frame) end, index, "SetTextureAsync callback")
			end
		end
	end
	previousIndex = index
end

-- Public methods
-- ============================================================================

-- Enqueue the given texture load in the current addon
function public.SetTextureAsync(frame, source, texture, weight, callback)
	-- Translate the string weight to a numerical value, default is "medium"
	if(type(weight) == "string") then
		weight = weights[weight] or weights.medium
	elseif(not weight or weight < 1) then
		weight = weights.medium
	end
	
	local addonIdentifier = InspectAddonCurrent()
	local frames = pendingList[addonIdentifier] or { }
	pendingList[addonIdentifier] = frames
	
	-- If the frame is already present in frames remove it
	for i = 1, #frames do
		if(frames[i][1] == frame) then
			tremove(frames, i)
			pendingTextures = pendingTextures - 1
			break
		end
	end
	
	frames[#frames + 1] = { frame, source, texture, weight, type(callback) == "function" and callback or nil }
	pendingTextures = pendingTextures + 1
end

-- Cancel the asynchronous loading for the given frame in the current addon
function public.CancelSetTextureAsync(frame)
	local addonIdentifier = InspectAddonCurrent()
	local frames = pendingList[addonIdentifier]
	if(frames) then
		for i = 1, #frames do
			if(frames[i][1] == frame) then
				tremove(frames, i)
				pendingTextures = pendingTextures - 1
				return
			end
		end
	end
end

-- Cancel all currently pending textures for the current addon
function public.CancelAllPendingTextures()
	pendingList[InspectAddonCurrent()] = { }
end

-- Return how many textures are pending in the current addon
function public.GetNumPendingTextures()
	local addonIdentifier = InspectAddonCurrent()
	local frames = pendingList[addonIdentifier]
	return frames and #frames or 0
end

-- Initialization
-- ============================================================================

-- Create a dummy Texture frame to get it's metatable and add applicable methods to it
local texture = UI.CreateFrame("Texture", "Dummy", UI.CreateContext("LibAsyncTexture"))
texture:SetVisible(false)
local meta = getmetatable(texture)
meta.__index.SetTextureAsync = public.SetTextureAsync
meta.__index.CancelSetTextureAsync = public.CancelSetTextureAsync

local event = { loadTextures, Addon.identifier, "loadTextures" }
Event.System.Update.End[#Event.System.Update.End + 1] = event