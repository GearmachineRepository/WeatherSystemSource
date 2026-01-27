--!strict

local OceanConfig = require(script.Parent.OceanConfig)

local BoneGrid = {}
BoneGrid.__index = BoneGrid

export type BoneGrid = typeof(setmetatable({} :: {
	Mesh: MeshPart,
	Grid: { [number]: { [number]: Bone } },
	OriginalPositions: { [Bone]: Vector3 },
	Bones: { Bone },
	GridSpacing: number,
	GridOrigin: Vector3,
	MinX: number,
	MaxX: number,
	MinZ: number,
	MaxZ: number,
	GridSizeX: number,
	GridSizeZ: number,
}, BoneGrid))

function BoneGrid.new(OceanMesh: MeshPart): BoneGrid
	local self = setmetatable({}, BoneGrid) :: any

	self.Mesh = OceanMesh
	self.Grid = {}
	self.OriginalPositions = {}
	self.Bones = {}
	self.GridSpacing = 0
	self.GridOrigin = Vector3.new(0, 0, 0)
	self.MinX = math.huge
	self.MaxX = -math.huge
	self.MinZ = math.huge
	self.MaxZ = -math.huge
	self.GridSizeX = 0
	self.GridSizeZ = 0

	self:_CollectBones()
	self:_DetectGridLayout()
	self:_BuildGrid()

	return self
end

function BoneGrid._CollectBones(self: BoneGrid): ()
	for _, Child in pairs(self.Mesh:GetDescendants()) do
		if Child:IsA("Bone") then
			local BoneInstance = Child :: Bone
			table.insert(self.Bones, BoneInstance)
			self.OriginalPositions[BoneInstance] = BoneInstance.WorldPosition

			local Position = Child.WorldPosition
			self.MinX = math.min(self.MinX, Position.X)
			self.MaxX = math.max(self.MaxX, Position.X)
			self.MinZ = math.min(self.MinZ, Position.Z)
			self.MaxZ = math.max(self.MaxZ, Position.Z)
		end
	end
end

function BoneGrid._DetectGridLayout(self: BoneGrid): ()
	if #self.Bones < 2 then
		warn("[BoneGrid] Not enough bones to detect grid layout")
		self.GridSpacing = OceanConfig.GRID_SPACING
		return
	end

	local SortedByX: { Vector3 } = {}
	for _, Bone in self.Bones do
		table.insert(SortedByX, self.OriginalPositions[Bone])
	end

	table.sort(SortedByX, function(PositionA: Vector3, PositionB: Vector3): boolean
		return PositionA.X < PositionB.X
	end)

	local MinGap = math.huge
	for Index = 2, #SortedByX do
		local Gap = math.abs(SortedByX[Index].X - SortedByX[Index - 1].X)
		if Gap > 0.1 then
			MinGap = math.min(MinGap, Gap)
		end
	end

	if MinGap < math.huge and MinGap > 0.1 then
		self.GridSpacing = MinGap
	else
		self.GridSpacing = OceanConfig.GRID_SPACING
	end

	self.GridOrigin = Vector3.new(self.MinX, OceanConfig.BASE_WATER_HEIGHT, self.MinZ)
	self.GridSizeX = math.ceil((self.MaxX - self.MinX) / self.GridSpacing) + 1
	self.GridSizeZ = math.ceil((self.MaxZ - self.MinZ) / self.GridSpacing) + 1
end

function BoneGrid._BuildGrid(self: BoneGrid): ()
	for _, Bone in self.Bones do
		local Position = self.OriginalPositions[Bone]
		local GridX, GridZ = self:WorldToGrid(Position)

		if not self.Grid[GridX] then
			self.Grid[GridX] = {}
		end

		if self.Grid[GridX][GridZ] then
			local ExistingPosition = self.OriginalPositions[self.Grid[GridX][GridZ]]
			local CellCenter = self:GridToWorld(GridX, GridZ)
			local ExistingDistance = (ExistingPosition - CellCenter).Magnitude
			local NewDistance = (Position - CellCenter).Magnitude

			if NewDistance < ExistingDistance then
				self.Grid[GridX][GridZ] = Bone
			end
		else
			self.Grid[GridX][GridZ] = Bone
		end
	end
end

function BoneGrid.WorldToGrid(self: BoneGrid, WorldPosition: Vector3): (number, number)
	local Relative = WorldPosition - self.GridOrigin
	local GridX = math.floor(Relative.X / self.GridSpacing + 0.5)
	local GridZ = math.floor(Relative.Z / self.GridSpacing + 0.5)
	return GridX, GridZ
end

function BoneGrid.GridToWorld(self: BoneGrid, GridX: number, GridZ: number): Vector3
	return self.GridOrigin + Vector3.new(
		GridX * self.GridSpacing,
		0,
		GridZ * self.GridSpacing
	)
end

function BoneGrid.GetBoneAt(self: BoneGrid, GridX: number, GridZ: number): Bone?
	if self.Grid[GridX] then
		return self.Grid[GridX][GridZ]
	end
	return nil
end

function BoneGrid.GetSurroundingBones(self: BoneGrid, WorldPosition: Vector3): (Bone?, Bone?, Bone?, Bone?)
	local Relative = WorldPosition - self.GridOrigin
	local FloatX = Relative.X / self.GridSpacing
	local FloatZ = Relative.Z / self.GridSpacing

	local GridX = math.floor(FloatX)
	local GridZ = math.floor(FloatZ)

	local TopLeft = self:GetBoneAt(GridX, GridZ)
	local TopRight = self:GetBoneAt(GridX + 1, GridZ)
	local BottomLeft = self:GetBoneAt(GridX, GridZ + 1)
	local BottomRight = self:GetBoneAt(GridX + 1, GridZ + 1)

	return TopLeft, TopRight, BottomLeft, BottomRight
end

function BoneGrid.GetTriangleForPosition(
	self: BoneGrid,
	WorldPosition: Vector3,
	TopLeft: Bone,
	TopRight: Bone,
	BottomLeft: Bone,
	BottomRight: Bone
): (Bone, Bone, Bone)
	local Relative = WorldPosition - self.GridOrigin
	local FloatX = Relative.X / self.GridSpacing
	local FloatZ = Relative.Z / self.GridSpacing

	local LocalX = math.clamp(FloatX - math.floor(FloatX), 0, 1)
	local LocalZ = math.clamp(FloatZ - math.floor(FloatZ), 0, 1)

	if LocalX + LocalZ < 1 then
		return TopLeft, TopRight, BottomLeft
	else
		return TopRight, BottomRight, BottomLeft
	end
end

function BoneGrid.GetOriginalPosition(self: BoneGrid, Bone: Bone): Vector3
	return self.OriginalPositions[Bone]
end

function BoneGrid.GetAllBones(self: BoneGrid): {Bone}
	return self.Bones
end

function BoneGrid.IsInBounds(self: BoneGrid, WorldPosition: Vector3): boolean
	local Relative = WorldPosition - self.GridOrigin
	local FloatX = Relative.X / self.GridSpacing
	local FloatZ = Relative.Z / self.GridSpacing

	return FloatX >= 0 and FloatX < self.GridSizeX - 1
		and FloatZ >= 0 and FloatZ < self.GridSizeZ - 1
end

function BoneGrid.GetSpacing(self: BoneGrid): number
	return self.GridSpacing
end

return BoneGrid