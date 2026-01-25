--[[
    WaveHeightSampler
    Samples wave height at any position using triangle interpolation.

    This reads the ACTUAL bone positions (including Transform) to get heights
    that match the visual mesh exactly.
]]

local WaveConfig = require(script.Parent.WaveConfig)
local BoneGrid = require(script.Parent.BoneGrid)

local WaveHeightSampler = {}
WaveHeightSampler.__index = WaveHeightSampler

-- Module-level reference to the active sampler
local ActiveSampler = nil

--[[
    Create a new WaveHeightSampler.

    Parameters:
        OceanMesh: MeshPart/Part - The skinned mesh with bones

    Returns:
        WaveHeightSampler instance
]]
function WaveHeightSampler.new(OceanMesh)
	local self = setmetatable({}, WaveHeightSampler)

	self.BoneGrid = BoneGrid.new(OceanMesh)
	self.OceanMesh = OceanMesh

	-- Set as active sampler
	ActiveSampler = self

	return self
end

--[[
    Get the active sampler instance.
]]
function WaveHeightSampler.GetActive()
	return ActiveSampler
end

--[[
    Get the current animated position of a bone.
    This includes the Transform displacement.

    Parameters:
        Bone: Bone

    Returns:
        Vector3 - The current world position including animation
]]
function WaveHeightSampler:_GetAnimatedBonePosition(Bone)
	-- WorldPosition is the rest position in world space
	-- Transform.Position is the displacement applied by the wave animation
	local RestPosition = Bone.WorldPosition
	local TransformOffset = Bone.Transform.Position
	return RestPosition + TransformOffset
end

--[[
    Project a point vertically onto the plane formed by three vertices.

    Parameters:
        Position: Vector3 - The point to project (only X and Z are used)
        VertexA, VertexB, VertexC: Vector3 - The three vertices of the triangle

    Returns:
        number - The Y height on the plane at that X, Z
]]
function WaveHeightSampler:_ProjectToTrianglePlane(Position, VertexA, VertexB, VertexC)
	local AB = VertexB - VertexA
	local AC = VertexC - VertexA
	local Normal = AB:Cross(AC)

	-- Handle degenerate triangles
	if Normal.Magnitude < 0.0001 then
		return (VertexA.Y + VertexB.Y + VertexC.Y) / 3
	end

	Normal = Normal.Unit

	-- Make sure normal points up
	if Normal.Y < 0 then
		Normal = -Normal
	end

	-- Avoid division by zero
	if math.abs(Normal.Y) < 0.0001 then
		return (VertexA.Y + VertexB.Y + VertexC.Y) / 3
	end

	-- Project the position onto the plane
	local Offset = Position - VertexA
	local Y = -(Normal.X * Offset.X + Normal.Z * Offset.Z) / Normal.Y

	return VertexA.Y + Y
end

--[[
    Get the wave height at a world position using triangle interpolation.
    This gives you the EXACT height that matches the visual mesh.

    Parameters:
        X: number - World X position
        Z: number - World Z position

    Returns:
        number - The Y height of the wave surface
]]
function WaveHeightSampler:GetHeight(X, Z)
	local WorldPosition = Vector3.new(X, 0, Z)

	-- Check if position is within the grid
	if not self.BoneGrid:IsInBounds(WorldPosition) then
		-- Fall back to base water height outside the grid
		return WaveConfig.BaseWaterHeight
	end

	-- Get the four bones forming the quad
	local TopLeft, TopRight, BottomLeft, BottomRight = self.BoneGrid:GetSurroundingBones(WorldPosition)

	if not (TopLeft and TopRight and BottomLeft and BottomRight) then
		return WaveConfig.BaseWaterHeight
	end

	-- Determine which triangle we're in
	local BoneA, BoneB, BoneC = self.BoneGrid:GetTriangleForPosition(
		WorldPosition, TopLeft, TopRight, BottomLeft, BottomRight
	)

	if not (BoneA and BoneB and BoneC) then
		return WaveConfig.BaseWaterHeight
	end

	-- Get the ANIMATED positions of these bones (includes Transform)
	local PosA = self:_GetAnimatedBonePosition(BoneA)
	local PosB = self:_GetAnimatedBonePosition(BoneB)
	local PosC = self:_GetAnimatedBonePosition(BoneC)

	-- Project our position onto the triangle plane
	return self:_ProjectToTrianglePlane(WorldPosition, PosA, PosB, PosC)
end

--[[
    Get wave height at a Vector3 position.
]]
function WaveHeightSampler:GetHeightAtPosition(Position)
	return self:GetHeight(Position.X, Position.Z)
end

--[[
    Check if a position is underwater.
]]
function WaveHeightSampler:IsUnderwater(Position)
	local WaveHeight = self:GetHeight(Position.X, Position.Z)
	return Position.Y < WaveHeight
end

--[[
    Get depth below surface.
]]
function WaveHeightSampler:GetDepth(Position)
	local WaveHeight = self:GetHeight(Position.X, Position.Z)
	return WaveHeight - Position.Y
end

return WaveHeightSampler