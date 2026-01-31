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

local GRID_SIZE = 3
local HALF_GRID = math.floor(GRID_SIZE / 2)

export type TileData = {
	Model: Model,
	Mesh: MeshPart,
	Bones: {Bone},
	GridX: number,
	GridZ: number,
}

export type OceanTileManager = typeof(setmetatable({} :: {
	TileTemplate: Model,
	TileSize: number,
	TileContainer: Folder,
	Tiles: {TileData},
	CurrentGridX: number,
	CurrentGridZ: number,
	MaxUpdateDistance: number,
	MaxUpdateDistanceSquared: number,
	Running: boolean,
	TextureEnabled: boolean,
	TextureSettings: OceanTexture.OceanTextureConfig?,
	TextureVariants: {string},
	TextureFrameRate: number,
	CurrentTextureFrame: number,
	TextureTiles: {TileData},
	TextureTileRefreshInterval: number,
	TextureTileRefreshAccumulator: number,
	WaveUpdateInterval: number,
	WaveUpdateAccumulator: number,
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

local function GridToWorld(GridX: number, GridZ: number, TileSize: number): Vector3
	local WorldX = GridX * TileSize
	local WorldZ = GridZ * TileSize
	return Vector3.new(WorldX, OceanSettings.GetBaseWaterHeight(), WorldZ)
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
	self._Trove = Trove.new()

	self.Tiles = {}
	self.CurrentGridX = 0
	self.CurrentGridZ = 0

	local Container = Instance.new("Folder")
	Container.Name = "OceanTiles"
	Container.Parent = workspace
	self.TileContainer = Container
	self._Trove:Add(Container)

	return self
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

function OceanTileManager.EnableTextures(self: OceanTileManager, Settings: OceanTexture.OceanTextureConfig): ()
	self.TextureEnabled = true
	self.TextureSettings = Settings
	self.TextureFrameRate = Settings.FrameRate or 12

	local FolderName = Settings.FolderName or "OceanMaterialVariants"
	self:_LoadTextureVariants(FolderName)
	self:_RefreshTextureTiles()
end

function OceanTileManager._CreateTile(self: OceanTileManager, GridX: number, GridZ: number): TileData
	local Model = self.TileTemplate:Clone()
	local Mesh = Model.PrimaryPart :: MeshPart

	if not Mesh then
		error("[OceanTileManager] TileTemplate has no PrimaryPart")
	end

	local WorldPosition = GridToWorld(GridX, GridZ, self.TileSize)
	Model.Parent = self.TileContainer
	Mesh.CFrame = CFrame.new(WorldPosition)

	local Bones = CollectBones(Mesh)

	local TileData: TileData = {
		Model = Model,
		Mesh = Mesh,
		Bones = Bones,
		GridX = GridX,
		GridZ = GridZ,
	}

	return TileData
end

function OceanTileManager._RepositionTile(self: OceanTileManager, Tile: TileData, GridX: number, GridZ: number): ()
	Tile.GridX = GridX
	Tile.GridZ = GridZ

	local WorldPosition = GridToWorld(GridX, GridZ, self.TileSize)
	Tile.Mesh.CFrame = CFrame.new(WorldPosition)

	for _, Bone in Tile.Bones do
		Bone.Transform = CFrame.new()
	end
end

function OceanTileManager._InitializeTiles(self: OceanTileManager): ()
	local PlayerPosition = GetPlayerPosition() :: Vector3
	if not PlayerPosition then
		PlayerPosition = Vector3.zero
	end

	local CenterGridX, CenterGridZ = WorldToGrid(PlayerPosition, self.TileSize)
	self.CurrentGridX = CenterGridX
	self.CurrentGridZ = CenterGridZ

	for OffsetX = -HALF_GRID, HALF_GRID do
		for OffsetZ = -HALF_GRID, HALF_GRID do
			local GridX = CenterGridX + OffsetX
			local GridZ = CenterGridZ + OffsetZ
			local Tile = self:_CreateTile(GridX, GridZ)
			table.insert(self.Tiles, Tile)
		end
	end
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

	local TilesToReposition: {TileData} = {}
	local OccupiedPositions: {[string]: boolean} = {}

	for _, Tile in self.Tiles do
		local Key = Tile.GridX .. "," .. Tile.GridZ
		if NeededPositions[Key] then
			OccupiedPositions[Key] = true
		else
			table.insert(TilesToReposition, Tile)
		end
	end

	local RepositionIndex = 1
	for OffsetX = -HALF_GRID, HALF_GRID do
		for OffsetZ = -HALF_GRID, HALF_GRID do
			local GridX = NewGridX + OffsetX
			local GridZ = NewGridZ + OffsetZ
			local Key = GridX .. "," .. GridZ

			if not OccupiedPositions[Key] then
				local Tile = TilesToReposition[RepositionIndex]
				if Tile then
					self:_RepositionTile(Tile, GridX, GridZ)
					RepositionIndex = RepositionIndex + 1
				end
			end
		end
	end
end

function OceanTileManager._UpdateWaves(self: OceanTileManager): ()
	local Time = GerstnerWave.GetSyncedTime()
	local Waves = OceanSettings.GetWaves()

	local PlayerPosition = GetPlayerPosition()
	local MaxDistanceSquared = self.MaxUpdateDistanceSquared

	for _, Tile in self.Tiles do
		for _, Bone in Tile.Bones do
			local WorldPosition = Bone.WorldPosition

			local ShouldUpdate = true
			if PlayerPosition then
				local Delta = WorldPosition - PlayerPosition
				local DistanceSquared = Delta.X * Delta.X + Delta.Z * Delta.Z
				ShouldUpdate = DistanceSquared < MaxDistanceSquared
			end

			if ShouldUpdate then
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

function OceanTileManager._RefreshTextureTiles(self: OceanTileManager): ()
	local PlayerPosition = GetPlayerPosition()
	if not PlayerPosition then
		return
	end

	local NearbyTiles: {TileData} = {}
	local EdgeThreshold = 200
	local HalfTile = self.TileSize / 2

	for _, Tile in self.Tiles do
		local TileCenter = Tile.Mesh.Position
		local IsCurrentTile = Tile.GridX == self.CurrentGridX and Tile.GridZ == self.CurrentGridZ

		if IsCurrentTile then
			table.insert(NearbyTiles, Tile)
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
            table.insert(NearbyTiles, Tile)
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

	for _, Tile in self.TextureTiles do
		Tile.Mesh.MaterialVariant = VariantName
	end
end

function OceanTileManager._Update(self: OceanTileManager, DeltaTime: number): ()
	self:_UpdateTilePositions()

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

	for _, Tile in self.Tiles do
		Tile.Model:Destroy()
	end
	self.Tiles = {}
end

function OceanTileManager.GetTileAtPosition(self: OceanTileManager, Position: Vector3): TileData?
	local GridX, GridZ = WorldToGrid(Position, self.TileSize)

	for _, Tile in self.Tiles do
		if Tile.GridX == GridX and Tile.GridZ == GridZ then
			return Tile
		end
	end

	return nil
end

function OceanTileManager.SetWaveUpdateRate(self: OceanTileManager, UpdatesPerSecond: number): ()
	self.WaveUpdateInterval = 1 / math.max(1, UpdatesPerSecond)
end

function OceanTileManager.Destroy(self: OceanTileManager): ()
	self:Stop()
	self._Trove:Destroy()
end

return OceanTileManager