--!strict
-- MapTransform
-- Phase 2: the mathematical core of the world map.
--
-- Converts between world space (studs) and normalized map space (0..1, 0..1).
-- Normalized space: (0,0) = top-left of the image, (1,1) = bottom-right.
--
-- Orientation (verified empirically against player movement):
--   u (horizontal) tracks world X:  -X = left,  +X = right
--   v (vertical)   tracks world Z:  -Z = up,    +Z = down
-- West->left, East->right, South->down, North->up. No transpose, no flips.

local MapConfig = require(script.Parent.MapConfig)

local MapTransform = {}

-- World (X, Z) -> normalized (u, v) in [0, 1]. Y ignored (flat world).
function MapTransform.worldToNormalized(worldX: number, worldZ: number): (number, number)
	local minX, minZ, maxX, maxZ = MapConfig.getBounds()
	local spanX = maxX - minX
	local spanZ = maxZ - minZ

	if spanX == 0 or spanZ == 0 then
		warn("[MapTransform] Degenerate bounds (zero span). Check MapBound markers.")
		return 0.5, 0.5
	end

	local u = (worldX - minX) / spanX
	local v = (worldZ - minZ) / spanZ
	return u, v
end

function MapTransform.vectorToNormalized(pos: Vector3): (number, number)
	return MapTransform.worldToNormalized(pos.X, pos.Z)
end

-- Normalized (u, v) -> world (X, Z). Inverse of the above.
function MapTransform.normalizedToWorld(u: number, v: number): (number, number)
	local minX, minZ, maxX, maxZ = MapConfig.getBounds()
	local worldX = minX + u * (maxX - minX)
	local worldZ = minZ + v * (maxZ - minZ)
	return worldX, worldZ
end

function MapTransform.clampNormalized(u: number, v: number): (number, number)
	return math.clamp(u, 0, 1), math.clamp(v, 0, 1)
end

function MapTransform.isOnMap(u: number, v: number): boolean
	return u >= 0 and u <= 1 and v >= 0 and v <= 1
end

return MapTransform
