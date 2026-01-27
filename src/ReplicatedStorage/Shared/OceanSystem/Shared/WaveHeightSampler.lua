--!strict

local OceanConfig = require(script.Parent.OceanConfig)
local BoneGrid = require(script.Parent.BoneGrid)


local WaveHeightSampler = {}
WaveHeightSampler.__index = WaveHeightSampler

export type WaveHeightSampler = typeof(setmetatable({} :: {
	BoneGrid: BoneGrid.BoneGrid,
	OceanMesh: MeshPart,
}, WaveHeightSampler))

local ActiveSampler: WaveHeightSampler? = nil

function WaveHeightSampler.new(OceanMesh: MeshPart): WaveHeightSampler
	local self = setmetatable({}, WaveHeightSampler) :: any

	self.BoneGrid = BoneGrid.new(OceanMesh)
	self.OceanMesh = OceanMesh

	ActiveSampler = self

	return self
end

function WaveHeightSampler.GetActive(): WaveHeightSampler?
	return ActiveSampler
end

function WaveHeightSampler._GetAnimatedBonePosition(_self: WaveHeightSampler, Bone: Bone): Vector3
	local RestPosition = Bone.WorldPosition
	local TransformOffset = Bone.Transform.Position
	return RestPosition + TransformOffset
end

function WaveHeightSampler._ProjectToTrianglePlane(
	_self: WaveHeightSampler,
	Position: Vector3,
	VertexA: Vector3,
	VertexB: Vector3,
	VertexC: Vector3
): number
	local EdgeAB = VertexB - VertexA
	local EdgeAC = VertexC - VertexA
	local Normal = EdgeAB:Cross(EdgeAC)

	if Normal.Magnitude < 0.0001 then
		return (VertexA.Y + VertexB.Y + VertexC.Y) / 3
	end

	Normal = Normal.Unit

	if Normal.Y < 0 then
		Normal = -Normal
	end

	if math.abs(Normal.Y) < 0.0001 then
		return (VertexA.Y + VertexB.Y + VertexC.Y) / 3
	end

	local Offset = Position - VertexA
	local HeightOffset = -(Normal.X * Offset.X + Normal.Z * Offset.Z) / Normal.Y

	return VertexA.Y + HeightOffset
end

function WaveHeightSampler.GetHeight(self: WaveHeightSampler, PositionX: number, PositionZ: number): number
	local WorldPosition = Vector3.new(PositionX, 0, PositionZ)

	if not self.BoneGrid:IsInBounds(WorldPosition) then
		return OceanConfig.BASE_WATER_HEIGHT
	end

	local TopLeft, TopRight, BottomLeft, BottomRight = self.BoneGrid:GetSurroundingBones(WorldPosition)

	if not (TopLeft and TopRight and BottomLeft and BottomRight) then
		return OceanConfig.BASE_WATER_HEIGHT
	end

	local BoneA, BoneB, BoneC = self.BoneGrid:GetTriangleForPosition(
		WorldPosition,
		TopLeft,
		TopRight,
		BottomLeft,
		BottomRight
	)

	if not (BoneA and BoneB and BoneC) then
		return OceanConfig.BASE_WATER_HEIGHT
	end

	local PositionA = self:_GetAnimatedBonePosition(BoneA)
	local PositionB = self:_GetAnimatedBonePosition(BoneB)
	local PositionC = self:_GetAnimatedBonePosition(BoneC)

	return self:_ProjectToTrianglePlane(WorldPosition, PositionA, PositionB, PositionC)
end

function WaveHeightSampler.GetHeightAtPosition(self: WaveHeightSampler, Position: Vector3): number
	return self:GetHeight(Position.X, Position.Z)
end

function WaveHeightSampler.IsUnderwater(self: WaveHeightSampler, Position: Vector3): boolean
	local WaveHeight = self:GetHeight(Position.X, Position.Z)
	return Position.Y < WaveHeight
end

function WaveHeightSampler.GetDepth(self: WaveHeightSampler, Position: Vector3): number
	local WaveHeight = self:GetHeight(Position.X, Position.Z)
	return WaveHeight - Position.Y
end

return WaveHeightSampler