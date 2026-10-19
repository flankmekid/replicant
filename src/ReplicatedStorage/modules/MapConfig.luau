--!strict
-- SPDX-License-Identifier: MIT
--
-- The settings of the world map: the map image and the two Workspace marker parts that
-- set the map bounds. MapTransform and the map UI read them. The image ratio (0.888)
-- matches the world ratio, so the map needs no distortion or axis flip.

local Workspace = game:GetService("Workspace")

local MapConfig = {}

-- The map image.
MapConfig.IMAGE_ID = "rbxassetid://83720184302193"

-- The pixel size of the image, for aspect-correct UI sizing.
MapConfig.IMAGE_WIDTH = 888
MapConfig.IMAGE_HEIGHT = 1000

-- The corner marker parts in workspace.worldMap. Min is the top-left of the map
-- (lowest X and Z), and Max is the bottom-right.
MapConfig.BOUND_FOLDER = "worldMap"
MapConfig.BOUND_MIN = "MapBound_Min"
MapConfig.BOUND_MAX = "MapBound_Max"

-- MapConfig.getBounds() - read the map bounds from the marker parts
--
-- Raises an error if a marker is missing, because every map system needs them.
--
-- Return: minX, minZ, maxX, maxZ.
function MapConfig.getBounds(): (number, number, number, number)
	local folder = Workspace:FindFirstChild(MapConfig.BOUND_FOLDER)
	assert(folder, `[MapConfig] workspace.{MapConfig.BOUND_FOLDER} is missing.`)

	local minPart = folder:FindFirstChild(MapConfig.BOUND_MIN)
	local maxPart = folder:FindFirstChild(MapConfig.BOUND_MAX)
	assert(
		minPart and minPart:IsA("BasePart"),
		`[MapConfig] {MapConfig.BOUND_MIN} is missing or is not a BasePart.`
	)
	assert(
		maxPart and maxPart:IsA("BasePart"),
		`[MapConfig] {MapConfig.BOUND_MAX} is missing or is not a BasePart.`
	)

	local a = (minPart :: BasePart).Position
	local b = (maxPart :: BasePart).Position

	-- Compute min and max from the positions, so it does not matter which part is which.
	local minX = math.min(a.X, b.X)
	local maxX = math.max(a.X, b.X)
	local minZ = math.min(a.Z, b.Z)
	local maxZ = math.max(a.Z, b.Z)

	return minX, minZ, maxX, maxZ
end

-- MapConfig.getImageAspect() - get the aspect ratio of the map image
--
-- Return: the width divided by the height.
function MapConfig.getImageAspect(): number
	return MapConfig.IMAGE_WIDTH / MapConfig.IMAGE_HEIGHT
end

return MapConfig
