--[[
    BoneGrid
    Manages the bone grid structure for O(1) lookups.

    This version auto-detects the grid layout from bone positions,
    so it works regardless of how bones are named (1, 2, 3... or Bone_X_Z, etc.)
]]

local WaveConfig = require(script.Parent.WaveConfig)

local BoneGrid = {}
BoneGrid.__index = BoneGrid

--[[
    Create a new BoneGrid from an ocean mesh.

    Parameters:
        OceanMesh: MeshPart/Part - The mesh with bones

    Returns:
        BoneGrid instance
]]
function BoneGrid.new(OceanMesh)
	local self = setmetatable({}, BoneGrid)

	self.Mesh = OceanMesh
	self.Grid = {}              -- 2D array: Grid[GridX][GridZ] = Bone
	self.OriginalPositions = {} -- Cache of original bone positions
	self.Bones = {}             -- Flat list of all bones
	self.GridSpacing = 0        -- Auto-detected spacing
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

--[[
    Collect all bones and cache original positions.
]]
function BoneGrid:_CollectBones()
	for _, Child in pairs(self.Mesh:GetDescendants()) do
		if Child:IsA("Bone") then
			table.insert(self.Bones, Child)
			self.OriginalPositions[Child] = Child.WorldPosition

			-- Track bounds
			local Pos = Child.WorldPosition
			self.MinX = math.min(self.MinX, Pos.X)
			self.MaxX = math.max(self.MaxX, Pos.X)
			self.MinZ = math.min(self.MinZ, Pos.Z)
			self.MaxZ = math.max(self.MaxZ, Pos.Z)
		end
	end
end

--[[
    Auto-detect the grid spacing and layout from bone positions.
]]
function BoneGrid:_DetectGridLayout()
	if #self.Bones < 2 then
		warn("[BoneGrid] Not enough bones to detect grid layout")
		self.GridSpacing = WaveConfig.GridSpacing
		return
	end

	-- Sort bones by X position to find spacing
	local SortedByX = {}
	for _, Bone in ipairs(self.Bones) do
		table.insert(SortedByX, self.OriginalPositions[Bone])
	end
	table.sort(SortedByX, function(A, B)
		return A.X < B.X
	end)

	-- Find the smallest non-zero X gap (this is likely our grid spacing)
	local MinGap = math.huge
	for I = 2, #SortedByX do
		local Gap = math.abs(SortedByX[I].X - SortedByX[I - 1].X)
		if Gap > 0.1 then -- Ignore tiny gaps (same column)
			MinGap = math.min(MinGap, Gap)
		end
	end

	-- Use detected spacing or fall back to config
	if MinGap < math.huge and MinGap > 0.1 then
		self.GridSpacing = MinGap
	else
		self.GridSpacing = WaveConfig.GridSpacing
	end

	-- Set grid origin to the minimum corner
	self.GridOrigin = Vector3.new(self.MinX, WaveConfig.BaseWaterHeight, self.MinZ)

	-- Calculate grid dimensions
	self.GridSizeX = math.ceil((self.MaxX - self.MinX) / self.GridSpacing) + 1
	self.GridSizeZ = math.ceil((self.MaxZ - self.MinZ) / self.GridSpacing) + 1
end

--[[
    Build the grid structure by placing bones into grid cells based on position.
]]
function BoneGrid:_BuildGrid()
	for _, Bone in ipairs(self.Bones) do
		local Pos = self.OriginalPositions[Bone]
		local GridX, GridZ = self:WorldToGrid(Pos)

		if not self.Grid[GridX] then
			self.Grid[GridX] = {}
		end

		-- If there's already a bone in this cell, keep the one closest to cell center
		if self.Grid[GridX][GridZ] then
			local ExistingPos = self.OriginalPositions[self.Grid[GridX][GridZ]]
			local CellCenter = self:GridToWorld(GridX, GridZ)
			local ExistingDist = (ExistingPos - CellCenter).Magnitude
			local NewDist = (Pos - CellCenter).Magnitude

			if NewDist < ExistingDist then
				self.Grid[GridX][GridZ] = Bone
			end
		else
			self.Grid[GridX][GridZ] = Bone
		end
	end

	-- Count how many grid cells have bones
	local FilledCells = 0
	for _, Column in pairs(self.Grid) do
		for _, _ in pairs(Column) do
			FilledCells = FilledCells + 1
		end
	end
end

--[[
    Convert a world position to grid indices.

    Parameters:
        WorldPosition: Vector3

    Returns:
        GridX: number, GridZ: number
]]
function BoneGrid:WorldToGrid(WorldPosition)
	local Relative = WorldPosition - self.GridOrigin
	local GridX = math.floor(Relative.X / self.GridSpacing + 0.5)
	local GridZ = math.floor(Relative.Z / self.GridSpacing + 0.5)
	return GridX, GridZ
end

--[[
    Convert grid indices to world position (center of cell).

    Parameters:
        GridX: number, GridZ: number

    Returns:
        Vector3
]]
function BoneGrid:GridToWorld(GridX, GridZ)
	return self.GridOrigin + Vector3.new(
		GridX * self.GridSpacing,
		0,
		GridZ * self.GridSpacing
	)
end

--[[
    Get a bone at specific grid coordinates.

    Parameters:
        GridX: number, GridZ: number

    Returns:
        Bone or nil
]]
function BoneGrid:GetBoneAt(GridX, GridZ)
	if self.Grid[GridX] then
		return self.Grid[GridX][GridZ]
	end
	return nil
end

--[[
    Get the four bones forming the quad that contains a world position.

    Parameters:
        WorldPosition: Vector3

    Returns:
        TopLeft, TopRight, BottomLeft, BottomRight (Bones, may be nil if at edge)
]]
function BoneGrid:GetSurroundingBones(WorldPosition)
	-- Find which cell we're in
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

--[[
    Determine which triangle within a quad contains the position.
    Assumes triangulation pattern:
        TL----TR
        | \    |
        |  \   |
        |   \  |
        BL----BR

    Parameters:
        WorldPosition: Vector3
        TopLeft, TopRight, BottomLeft, BottomRight: Bones

    Returns:
        BoneA, BoneB, BoneC (the three bones forming the triangle)
]]
function BoneGrid:GetTriangleForPosition(WorldPosition, TopLeft, TopRight, BottomLeft, BottomRight)
	local Relative = WorldPosition - self.GridOrigin
	local FloatX = Relative.X / self.GridSpacing
	local FloatZ = Relative.Z / self.GridSpacing

	-- Get position within cell (0 to 1)
	local LocalX = FloatX - math.floor(FloatX)
	local LocalZ = FloatZ - math.floor(FloatZ)

	-- Clamp to valid range
	LocalX = math.clamp(LocalX, 0, 1)
	LocalZ = math.clamp(LocalZ, 0, 1)

	-- Determine which triangle based on the diagonal
	if LocalX + LocalZ < 1 then
		-- Upper-left triangle
		return TopLeft, TopRight, BottomLeft
	else
		-- Lower-right triangle
		return TopRight, BottomRight, BottomLeft
	end
end

--[[
    Get the original (rest) position of a bone.

    Parameters:
        Bone: Bone

    Returns:
        Vector3
]]
function BoneGrid:GetOriginalPosition(Bone)
	return self.OriginalPositions[Bone]
end

--[[
    Get all bones (for iteration).

    Returns:
        Array of Bones
]]
function BoneGrid:GetAllBones()
	return self.Bones
end

--[[
    Check if a position is within the grid bounds.

    Parameters:
        WorldPosition: Vector3

    Returns:
        boolean
]]
function BoneGrid:IsInBounds(WorldPosition)
	local Relative = WorldPosition - self.GridOrigin
	local FloatX = Relative.X / self.GridSpacing
	local FloatZ = Relative.Z / self.GridSpacing

	return FloatX >= 0 and FloatX < self.GridSizeX - 1
		and FloatZ >= 0 and FloatZ < self.GridSizeZ - 1
end

--[[
    Get the grid spacing.

    Returns:
        number
]]
function BoneGrid:GetSpacing()
	return self.GridSpacing
end

return BoneGrid