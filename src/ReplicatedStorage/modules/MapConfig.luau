--!strict
-- MapConfig
-- Single source of truth for the world map system.
-- The transform, the UI, and (later) POIs + fog of war all read from here.
--
-- Foundation locked during planning:
--   Map image : rbxassetid://83720184302193  (888 x 1000, ratio 0.888)
--   Bounds    : workspace.worldMap.MapBound_Min / MapBound_Max
--   Orientation (Roblox "Top" view): +X = screen right, +Z = screen down
--   Image ratio (0.888) matches world ratio (0.888) -> no distortion, no axis flips.

local Workspace = game:GetService("Workspace")

local MapConfig = {}

-- The uploaded, correctly-proportioned map image.
MapConfig.IMAGE_ID = "rbxassetid://83720184302193"

-- Native pixel dimensions of that image (used for aspect-correct UI sizing).
MapConfig.IMAGE_WIDTH = 888
MapConfig.IMAGE_HEIGHT = 1000

-- Names of the corner anchor parts inside workspace.worldMap.
MapConfig.BOUND_FOLDER = "worldMap"
MapConfig.BOUND_MIN = "MapBound_Min" -- lowest  X, lowest  Z  (top-left  on screen: -X left, -Z up)
MapConfig.BOUND_MAX = "MapBound_Max" -- highest X, highest Z  (bottom-right on screen: +X right, +Z down)

-- Reads the live marker positions from the workspace.
-- Returns minX, minZ, maxX, maxZ (numbers). Errors loudly if the markers are missing,
-- because every downstream system depends on these existing.
function MapConfig.getBounds(): (number, number, number, number)
	local folder = Workspace:FindFirstChild(MapConfig.BOUND_FOLDER)
	assert(folder, "[MapConfig] Missing workspace." .. MapConfig.BOUND_FOLDER)

	local minPart = folder:FindFirstChild(MapConfig.BOUND_MIN)
	local maxPart = folder:FindFirstChild(MapConfig.BOUND_MAX)
	assert(minPart and minPart:IsA("BasePart"), "[MapConfig] Missing/invalid " .. MapConfig.BOUND_MIN)
	assert(maxPart and maxPart:IsA("BasePart"), "[MapConfig] Missing/invalid " .. MapConfig.BOUND_MAX)

	local a = (minPart :: BasePart).Position
	local b = (maxPart :: BasePart).Position

	-- Be defensive: don't assume which part literally holds the smaller value.
	-- Whoever placed them, min/max are derived from the actual numbers.
	local minX = math.min(a.X, b.X)
	local maxX = math.max(a.X, b.X)
	local minZ = math.min(a.Z, b.Z)
	local maxZ = math.max(a.Z, b.Z)

	return minX, minZ, maxX, maxZ
end

-- Convenience: the image's aspect ratio (width / height).
function MapConfig.getImageAspect(): number
	return MapConfig.IMAGE_WIDTH / MapConfig.IMAGE_HEIGHT
end

return MapConfig
