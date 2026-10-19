--!strict
-- SPDX-License-Identifier: MIT
--
-- Converts between world space (studs) and normalized map space, where (0, 0) is the
-- top-left of the map image and (1, 1) the bottom-right. u follows world X (+X is
-- right) and v follows world Z (+Z is down), with no transpose or flip.

local MapConfig = require(script.Parent.MapConfig)

local MapTransform = {}

-- MapTransform.worldToNormalized() - convert a world position to map space
-- @worldX: the world X
-- @worldZ: the world Z
--
-- Y is ignored.
--
-- Return: u and v, or 0.5, 0.5 when the map bounds have zero size.
function MapTransform.worldToNormalized(worldX: number, worldZ: number): (number, number)
	local minX, minZ, maxX, maxZ = MapConfig.getBounds()
	local spanX = maxX - minX
	local spanZ = maxZ - minZ

	if spanX == 0 or spanZ == 0 then
		warn("[MapTransform] The map bounds have zero size. Check the MapBound markers.")
		return 0.5, 0.5
	end

	local u = (worldX - minX) / spanX
	local v = (worldZ - minZ) / spanZ
	return u, v
end

-- MapTransform.vectorToNormalized() - convert a Vector3 to map space
-- @pos: the world position
--
-- Return: u and v.
function MapTransform.vectorToNormalized(pos: Vector3): (number, number)
	return MapTransform.worldToNormalized(pos.X, pos.Z)
end

-- MapTransform.normalizedToWorld() - convert map space to a world position
-- @u: the horizontal map coordinate
-- @v: the vertical map coordinate
--
-- Return: the world X and Z.
function MapTransform.normalizedToWorld(u: number, v: number): (number, number)
	local minX, minZ, maxX, maxZ = MapConfig.getBounds()
	local worldX = minX + u * (maxX - minX)
	local worldZ = minZ + v * (maxZ - minZ)
	return worldX, worldZ
end

-- MapTransform.clampNormalized() - clamp map coordinates to the map
-- @u: the horizontal map coordinate
-- @v: the vertical map coordinate
--
-- Return: u and v, each clamped to 0 to 1.
function MapTransform.clampNormalized(u: number, v: number): (number, number)
	return math.clamp(u, 0, 1), math.clamp(v, 0, 1)
end

-- MapTransform.isOnMap() - check whether map coordinates are on the map
-- @u: the horizontal map coordinate
-- @v: the vertical map coordinate
--
-- Return: true if both are between 0 and 1.
function MapTransform.isOnMap(u: number, v: number): boolean
	return u >= 0 and u <= 1 and v >= 0 and v <= 1
end

return MapTransform
