local Addon, private = ...

-- Builtins
local getmetatable = getmetatable
local next = next
local pairs = pairs
local print = print
local tremove = table.remove

-- Globals
local dump = dump
local Event = Event
local Inspect = Inspect
local UI = UI

local pendingList = {
--[[
	[addon] = {
		[*] = { frame, identifier, texture, weight }
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
local loadPerUpdate = 64

-- The public interface table
local public = { }
LibAsyncTexture = public

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

--	log("start", pendingTextures)
	while(pendingTextures > 0 and loaded < loadPerUpdate) do
--		log("loop", pendingTextures, loaded)
--		dumpList()
		-- Load the textures in round-robin fashion i.e.
		-- One texture per addon, cycling all addons
		index, addon = next(pendingList, index)
		if(addon and #addon > 0) then
			local entry = tremove(addon, 1)
			entry[1]:SetTexture(entry[2], entry[3])
			loaded = loaded + entry[4]
			pendingTextures = pendingTextures - 1
		end
	end
--	log("end", pendingTextures, loaded)
	previousIndex = index
end

-- Public methods
-- ============================================================================

-- Enqueue the given texture load in the current addon
function public.SetTextureAsync(frame, identifier, texture, sizeHint)
	-- Translate the string weight to a numerical value, default is "medium"
	local weight = weights[sizeHint] or weights.medium
	
	local addonIdentifier = Inspect.Addon.Current()
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
	
	frames[#frames + 1] = { frame, identifier, texture, weight }
	pendingTextures = pendingTextures + 1
end

-- Cancel the asynchronous loading for the given frame in the current addon
function public.CancelSetTextureAsync(frame)
	local addonIdentifier = Inspect.Addon.Current()
	local frames = pendingList[addonIdentifier]
	if(frames) then
		for i = 1, #frames do
			if(frames[i] == frame) then
				tremove(frames, i)
				pendingTextures = pendingTextures - 1
				return
			end
		end
	end
end

-- Cancel all currently pending textures for the current addon
function public.CancelAllPendingTextures()
	pendingList[Inspect.Addon.Current()] = { }
end

-- Return how many textures are pending in the current addon
function public.GetNumPendingTextures()
	local addonIdentifier = Inspect.Addon.Current()
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
Event.System.Update.Begin[#Event.System.Update.Begin + 1] = event