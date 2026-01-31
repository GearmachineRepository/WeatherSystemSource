--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Trove = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Trove"))
local OceanSettings = require(script.Parent.Parent.Shared.OceanSettings)
local GerstnerWave = require(script.Parent.Parent.Shared.GerstnerWave)
local OceanTexture = require(script.Parent.OceanTexture)

local OceanTileManager = {}
OceanTileManager.__index = OceanTileManager

local GRID_SIZE = 9
local HALF_GRID = math.floor(GRID_SIZE / 2)
local MESH_POOL_SIZE = 9

export type MeshTileData = {
	Model: Model,
	Mesh: MeshPart,
	Bones: {Bone},
	InUse: boolean,
	GridX: number?,
	GridZ: number?,
}

export type PartTileData = {
	Part: Part,
	GridX: number,
	GridZ: number,
	HasMesh: boolean,
	AssignedMesh: MeshTileData?,
}

export type OceanTileManager = typeof(setmetatable({} :: {
	TileTemplate: Model,
	TileSize: number,
	TileContainer: Folder,
	PartTiles: {PartTileData},
	MeshPool: {MeshTileData},
	CurrentGridX: number,
	CurrentGridZ: number,
	MaxUpdateDistance: number,
	MaxUpdateDistanceSquared: number,
	MeshSwapDistance: number,
	MeshSwapDistanceSquared: number,
	Running: boolean,
	TextureEnabled: boolean,
	TextureSettings: OceanTexture.OceanTextureConfig?,
	TextureVariants: {string},
	TextureFrameRate: number,
	CurrentTextureFrame: number,
	TextureTiles: {PartTileData},
	TextureTileRefreshInterval: number,
	TextureTileRefreshAccumulator: number,
	WaveUpdateInterval: number,
	WaveUpdateAccumulator: number,
	LODRefreshInterval: number,
	LODRefreshAccumulator: number,
	PartColor: Color3,
	PartMaterial: Enum.Material,
	_Trove: typeof(Trove.new()),
}, OceanTileManager))

local function GetPlayerPosition(): Vector3?
	local LocalPlayer = Players.LocalPlayer
	if not LocalPlayer then
		return nil
	end

	local Character = LocalPlayer.Character
	if not Character then
		return nil
	end

	local PrimaryPart = Character.PrimaryPart
	if not PrimaryPart then
		return nil
	end

	return PrimaryPart.Position
end

local function WorldToGrid(Position: Vector3, TileSize: number): (number, number)
	local HalfTile = TileSize / 2
	local GridX = math.floor((Position.X + HalfTile) / TileSize)
	local GridZ = math.floor((Position.Z + HalfTile) / TileSize)
	return GridX, GridZ
end

local function GridToWorld(GridX: number, GridZ: number, TileSize: number, WaterHeight: number): Vector3
	local WorldX = GridX * TileSize
	local WorldZ = GridZ * TileSize
	return Vector3.new(WorldX, WaterHeight, WorldZ)
end

local function CollectBones(Mesh: MeshPart): {Bone}
	local Bones: {Bone} = {}
	for _, Descendant in Mesh:GetDescendants() do
		if Descendant:IsA("Bone") then
			table.insert(Bones, Descendant)
		end
	end
	return Bones
end

function OceanTileManager.new(TileTemplate: Model, TileSize: number, MaxUpdateDistance: number): OceanTileManager
	local self = setmetatable({}, OceanTileManager) :: any

	self.TileTemplate = TileTemplate
	self.TileSize = TileSize
	self.MaxUpdateDistance = MaxUpdateDistance
	self.MaxUpdateDistanceSquared = MaxUpdateDistance * MaxUpdateDistance
	self.MeshSwapDistance = 400
	self.MeshSwapDistanceSquared = 400 * 400
	self.Running = false
	self.TextureEnabled = false
	self.TextureSettings = nil
	self.TextureVariants = {}
	self.TextureFrameRate = 12
	self.CurrentTextureFrame = 0
	self.TextureTiles = {}
	self.TextureTileRefreshInterval = 0.5
	self.TextureTileRefreshAccumulator = 0
	self.WaveUpdateInterval = 1 / 60
	self.WaveUpdateAccumulator = 0
	self.LODRefreshInterval = 0.25
	self.LODRefreshAccumulator = 0
	self._Trove = Trove.new()

	self.PartTiles = {}
	self.MeshPool = {}
	self.CurrentGridX = 0
	self.CurrentGridZ = 0

	local TemplateMesh = TileTemplate.PrimaryPart :: MeshPart
	self.PartColor = TemplateMesh.Color
	self.PartMaterial = TemplateMesh.Material

	local Container = Instance.new("Folder")
	Container.Name = "OceanTiles"
	Container.Parent = workspace
	self.TileContainer = Container
	self._Trove:Add(Container)

	return self
end

function OceanTileManager._CreateMeshTile(self: OceanTileManager): MeshTileData
	local Model = self.TileTemplate:Clone()
	local Mesh = Model.PrimaryPart :: MeshPart

	if not Mesh then
		error("[OceanTileManager] TileTemplate has no PrimaryPart")
	end

	Model.Parent = self.TileContainer
	Model:PivotTo(CFrame.new(0, -10000, 0))

	local Bones = CollectBones(Mesh)

	return {
		Model = Model,
		Mesh = Mesh,
		Bones = Bones,
		InUse = false,
		GridX = nil,
		GridZ = nil,
	}
end

function OceanTileManager._CreatePartTile(self: OceanTileManager, GridX: number, GridZ: number): PartTileData
	local WaterHeight = OceanSettings.GetBaseWaterHeight()
	local WorldPosition = GridToWorld(GridX, GridZ, self.TileSize, WaterHeight)

	local TilePart = Instance.new("Part")
	TilePart.Name = "OceanPart"
	TilePart.Size = Vector3.new(self.TileSize, 0.1, self.TileSize)
	TilePart.CFrame = CFrame.new(WorldPosition)
	TilePart.Anchored = true
	TilePart.CanCollide = false
	TilePart.CanQuery = false
	TilePart.CanTouch = false
	TilePart.CastShadow = false
	TilePart.Color = self.PartColor
	TilePart.MaterialVariant = "1"
	TilePart.Material = self.PartMaterial
	TilePart.Parent = self.TileContainer

	return {
		Part = TilePart,
		GridX = GridX,
		GridZ = GridZ,
		HasMesh = false,
		AssignedMesh = nil,
	}
end

function OceanTileManager._InitializeMeshPool(self: OceanTileManager): ()
	for _ = 1, MESH_POOL_SIZE do
		local MeshTile = self:_CreateMeshTile()
		table.insert(self.MeshPool, MeshTile)
	end
end

function OceanTileManager._GetAvailableMesh(self: OceanTileManager): MeshTileData?
	for _, MeshTile in self.MeshPool do
		if not MeshTile.InUse then
			return MeshTile
		end
	end
	return nil
end

function OceanTileManager._AssignMeshToTile(self: OceanTileManager, PartTile: PartTileData): ()
	if PartTile.HasMesh then
		return
	end

	local MeshTile = self:_GetAvailableMesh()
	if not MeshTile then
		return
	end

	local WaterHeight = OceanSettings.GetBaseWaterHeight()
	local WorldPosition = GridToWorld(PartTile.GridX, PartTile.GridZ, self.TileSize, WaterHeight)

	MeshTile.Mesh.CFrame = CFrame.new(WorldPosition)
	MeshTile.InUse = true
	MeshTile.GridX = PartTile.GridX
	MeshTile.GridZ = PartTile.GridZ

	PartTile.HasMesh = true
	PartTile.AssignedMesh = MeshTile
	PartTile.Part.Transparency = 1
end

function OceanTileManager._ReleaseMeshFromTile(_self: OceanTileManager, PartTile: PartTileData): ()
	if not PartTile.HasMesh or not PartTile.AssignedMesh then
		return
	end

	local MeshTile = PartTile.AssignedMesh

	MeshTile.Model:PivotTo(CFrame.new(0, -10000, 0))
	MeshTile.InUse = false
	MeshTile.GridX = nil
	MeshTile.GridZ = nil

	for _, Bone in MeshTile.Bones do
		Bone.Transform = CFrame.new()
	end

	PartTile.HasMesh = false
	PartTile.AssignedMesh = nil
	PartTile.Part.Transparency = 0
end

function OceanTileManager._InitializeTiles(self: OceanTileManager): ()
	local PlayerPosition = GetPlayerPosition() :: Vector3
	if not PlayerPosition then
		PlayerPosition = Vector3.zero
	end

	local CenterGridX, CenterGridZ = WorldToGrid(PlayerPosition, self.TileSize)
	self.CurrentGridX = CenterGridX
	self.CurrentGridZ = CenterGridZ

	self:_InitializeMeshPool()

	for OffsetX = -HALF_GRID, HALF_GRID do
		for OffsetZ = -HALF_GRID, HALF_GRID do
			local GridX = CenterGridX + OffsetX
			local GridZ = CenterGridZ + OffsetZ
			local PartTile = self:_CreatePartTile(GridX, GridZ)
			table.insert(self.PartTiles, PartTile)
		end
	end

	self:_UpdateLOD()
end

function OceanTileManager._RepositionPartTile(self: OceanTileManager, PartTile: PartTileData, GridX: number, GridZ: number): ()
	if PartTile.HasMesh then
		self:_ReleaseMeshFromTile(PartTile)
	end

	PartTile.GridX = GridX
	PartTile.GridZ = GridZ

	local WaterHeight = OceanSettings.GetBaseWaterHeight()
	local WorldPosition = GridToWorld(GridX, GridZ, self.TileSize, WaterHeight)
	PartTile.Part.CFrame = CFrame.new(WorldPosition)
end

function OceanTileManager._UpdateTilePositions(self: OceanTileManager): ()
	local PlayerPosition = GetPlayerPosition()
	if not PlayerPosition then
		return
	end

	local NewGridX, NewGridZ = WorldToGrid(PlayerPosition, self.TileSize)

	if NewGridX == self.CurrentGridX and NewGridZ == self.CurrentGridZ then
		return
	end

	self.CurrentGridX = NewGridX
	self.CurrentGridZ = NewGridZ

	local NeededPositions: {[string]: boolean} = {}
	for OffsetX = -HALF_GRID, HALF_GRID do
		for OffsetZ = -HALF_GRID, HALF_GRID do
			local GridX = NewGridX + OffsetX
			local GridZ = NewGridZ + OffsetZ
			local Key = GridX .. "," .. GridZ
			NeededPositions[Key] = true
		end
	end

	local TilesToReposition: {PartTileData} = {}
	local OccupiedPositions: {[string]: boolean} = {}

	for _, PartTile in self.PartTiles do
		local Key = PartTile.GridX .. "," .. PartTile.GridZ
		if NeededPositions[Key] then
			OccupiedPositions[Key] = true
		else
			table.insert(TilesToReposition, PartTile)
		end
	end

	local RepositionIndex = 1
	for OffsetX = -HALF_GRID, HALF_GRID do
		for OffsetZ = -HALF_GRID, HALF_GRID do
			local GridX = NewGridX + OffsetX
			local GridZ = NewGridZ + OffsetZ
			local Key = GridX .. "," .. GridZ

			if not OccupiedPositions[Key] then
				local PartTile = TilesToReposition[RepositionIndex]
				if PartTile then
					self:_RepositionPartTile(PartTile, GridX, GridZ)
					RepositionIndex = RepositionIndex + 1
				end
			end
		end
	end
end

function OceanTileManager._UpdateLOD(self: OceanTileManager): ()
	local PlayerPosition = GetPlayerPosition()
	if not PlayerPosition then
		return
	end

	local SwapDistanceSquared = self.MeshSwapDistanceSquared

	for _, PartTile in self.PartTiles do
		local WaterHeight = OceanSettings.GetBaseWaterHeight()
		local TileCenter = GridToWorld(PartTile.GridX, PartTile.GridZ, self.TileSize, WaterHeight)
		local Delta = TileCenter - PlayerPosition
		local DistanceSquared = Delta.X * Delta.X + Delta.Z * Delta.Z

		if DistanceSquared < SwapDistanceSquared then
			if not PartTile.HasMesh then
				self:_AssignMeshToTile(PartTile)
			end
		else
			if PartTile.HasMesh then
				self:_ReleaseMeshFromTile(PartTile)
			end
		end
	end
end

function OceanTileManager._UpdateWaves(self: OceanTileManager): ()
	local Time = GerstnerWave.GetSyncedTime()
	local Waves = OceanSettings.GetWaves()

	local PlayerPosition = GetPlayerPosition()
	if not PlayerPosition then
		return
	end

	local MaxDistanceSquared = self.MaxUpdateDistanceSquared

	for _, MeshTile in self.MeshPool do
		if not MeshTile.InUse then
			continue
		end

		for _, Bone in MeshTile.Bones do
			local WorldPosition = Bone.WorldPosition

			local Delta = WorldPosition - PlayerPosition
			local DistanceSquared = Delta.X * Delta.X + Delta.Z * Delta.Z

			if DistanceSquared < MaxDistanceSquared then
				local TotalDisplacement = Vector3.zero

				for _, Wave in Waves do
					local Displacement = GerstnerWave.CalculateSingleWave(
						WorldPosition,
						Wave.Wavelength,
						Wave.Direction,
						Wave.Steepness,
						Wave.Gravity,
						Time
					)
					TotalDisplacement = TotalDisplacement + Displacement
				end

				local NoiseDisplacement = GerstnerWave.CalculateNoiseDisplacement(
					WorldPosition.X,
					WorldPosition.Z,
					Time
				)
				TotalDisplacement = TotalDisplacement + NoiseDisplacement

				Bone.Transform = CFrame.new(TotalDisplacement)
			else
				Bone.Transform = CFrame.new()
			end
		end
	end
end

function OceanTileManager._LoadTextureVariants(self: OceanTileManager, FolderName: string): ()
	local MaterialService = game:GetService("MaterialService")
	local VariantFolder = MaterialService:FindFirstChild(FolderName)

	if not VariantFolder then
		warn("[OceanTileManager] MaterialVariant folder not found:", FolderName)
		return
	end

	local Variants: {MaterialVariant} = {}
	for _, Child in VariantFolder:GetChildren() do
		if Child:IsA("MaterialVariant") then
			table.insert(Variants, Child)
		end
	end

	table.sort(Variants, function(VariantA, VariantB)
		local NumberA = tonumber(VariantA.Name) or 0
		local NumberB = tonumber(VariantB.Name) or 0
		return NumberA < NumberB
	end)

	for _, Variant in Variants do
		table.insert(self.TextureVariants, Variant.Name)
	end
end

function OceanTileManager._RefreshTextureTiles(self: OceanTileManager): ()
	local PlayerPosition = GetPlayerPosition()
	if not PlayerPosition then
		return
	end

	local NearbyTiles: {PartTileData} = {}
	local EdgeThreshold = 200
	local HalfTile = self.TileSize / 2

	for _, PartTile in self.PartTiles do
		local WaterHeight = OceanSettings.GetBaseWaterHeight()
		local TileCenter = GridToWorld(PartTile.GridX, PartTile.GridZ, self.TileSize, WaterHeight)
		local IsCurrentTile = PartTile.GridX == self.CurrentGridX and PartTile.GridZ == self.CurrentGridZ

		if IsCurrentTile then
			table.insert(NearbyTiles, PartTile)
			continue
		end

		local DeltaX = PlayerPosition.X - TileCenter.X
		local DeltaZ = PlayerPosition.Z - TileCenter.Z

		local DistanceToTileEdgeX = math.abs(DeltaX) - HalfTile
		local DistanceToTileEdgeZ = math.abs(DeltaZ) - HalfTile

        local NearX = DistanceToTileEdgeX < EdgeThreshold and DistanceToTileEdgeX > -HalfTile
        local NearZ = DistanceToTileEdgeZ < EdgeThreshold and DistanceToTileEdgeZ > -HalfTile

        local IsWithinZBounds = math.abs(DeltaZ) < HalfTile
        local IsWithinXBounds = math.abs(DeltaX) < HalfTile

        if (NearX and NearZ) or (NearX and IsWithinZBounds) or (NearZ and IsWithinXBounds) then
            table.insert(NearbyTiles, PartTile)
        end
	end

	self.TextureTiles = NearbyTiles
end

function OceanTileManager._UpdateTextures(self: OceanTileManager, DeltaTime: number): ()
	if not self.TextureEnabled or #self.TextureVariants == 0 then
		return
	end

	self.TextureTileRefreshAccumulator = self.TextureTileRefreshAccumulator + DeltaTime
	if self.TextureTileRefreshAccumulator >= self.TextureTileRefreshInterval then
		self.TextureTileRefreshAccumulator = 0
		self:_RefreshTextureTiles()
	end

	local Elapsed = workspace:GetServerTimeNow()
	local FrameIndex = math.floor(Elapsed * self.TextureFrameRate) % #self.TextureVariants + 1

	if FrameIndex == self.CurrentTextureFrame then
		return
	end

	self.CurrentTextureFrame = FrameIndex
	local VariantName = self.TextureVariants[FrameIndex]

	if not VariantName then
		return
	end

	for _, PartTile in self.TextureTiles do
		PartTile.Part.MaterialVariant = VariantName
		if PartTile.HasMesh and PartTile.AssignedMesh then
			PartTile.AssignedMesh.Mesh.MaterialVariant = VariantName
		end
	end
end

function OceanTileManager._Update(self: OceanTileManager, DeltaTime: number): ()
	self:_UpdateTilePositions()

	self.LODRefreshAccumulator = self.LODRefreshAccumulator + DeltaTime
	if self.LODRefreshAccumulator >= self.LODRefreshInterval then
		self.LODRefreshAccumulator = 0
		self:_UpdateLOD()
	end

	self.WaveUpdateAccumulator = self.WaveUpdateAccumulator + DeltaTime
	if self.WaveUpdateAccumulator >= self.WaveUpdateInterval then
		self.WaveUpdateAccumulator = self.WaveUpdateAccumulator - self.WaveUpdateInterval
		self:_UpdateWaves()
	end

	self:_UpdateTextures(DeltaTime)
end

function OceanTileManager.Start(self: OceanTileManager): ()
	if self.Running then
		return
	end

	self.Running = true

	local LocalPlayer = Players.LocalPlayer
	if LocalPlayer then
		if not LocalPlayer.Character then
			LocalPlayer.CharacterAdded:Wait()
		end
		local Character = LocalPlayer.Character
		if Character and not Character.PrimaryPart then
			Character:WaitForChild("HumanoidRootPart", 10)
		end
	end

	self:_InitializeTiles()

	self._Trove:Connect(RunService.RenderStepped, function(DeltaTime: number)
		if not game:IsLoaded() then
			return
		end
		self:_Update(DeltaTime)
	end)
end

function OceanTileManager.Stop(self: OceanTileManager): ()
	if not self.Running then
		return
	end

	self.Running = false
	self._Trove:Clean()

	for _, PartTile in self.PartTiles do
		PartTile.Part:Destroy()
	end
	self.PartTiles = {}

	for _, MeshTile in self.MeshPool do
		MeshTile.Model:Destroy()
	end
	self.MeshPool = {}
end

function OceanTileManager.EnableTextures(self: OceanTileManager, Settings: OceanTexture.OceanTextureConfig): ()
	self.TextureEnabled = true
	self.TextureSettings = Settings
	self.TextureFrameRate = Settings.FrameRate or 12

	local FolderName = Settings.FolderName or "OceanMaterialVariants"
	self:_LoadTextureVariants(FolderName)
	self:_RefreshTextureTiles()
end

function OceanTileManager.SetMeshSwapDistance(self: OceanTileManager, Distance: number): ()
	self.MeshSwapDistance = Distance
	self.MeshSwapDistanceSquared = Distance * Distance
end

function OceanTileManager.SetWaveUpdateRate(self: OceanTileManager, UpdatesPerSecond: number): ()
	self.WaveUpdateInterval = 1 / math.max(1, UpdatesPerSecond)
end

function OceanTileManager.GetTileAtPosition(self: OceanTileManager, Position: Vector3): PartTileData?
	local GridX, GridZ = WorldToGrid(Position, self.TileSize)

	for _, PartTile in self.PartTiles do
		if PartTile.GridX == GridX and PartTile.GridZ == GridZ then
			return PartTile
		end
	end

	return nil
end

function OceanTileManager.Destroy(self: OceanTileManager): ()
	self:Stop()
	self._Trove:Destroy()
end

return OceanTileManager